import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import Darwin
import DesignDatabaseCore
import Foundation
import Synchronization

public actor FileDesignDatabasePersistence: DesignDatabasePersisting {
  private static let lockedPaths = Mutex(Set<String>())

  private let rootURL: URL
  private let manifestURL: URL
  private let pendingWALURL: URL
  private let lockURL: URL
  private let digester: any ContentDigesting
  private var lockDescriptor: Int32
  private var isClosed: Bool

  public init(
    rootURL: URL,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) throws {
    guard rootURL.isFileURL else {
      throw DesignDatabaseError.persistence("Database root must be a file URL.")
    }
    let standardizedRoot = rootURL.standardizedFileURL
    try FileManager.default.createDirectory(
      at: standardizedRoot,
      withIntermediateDirectories: true
    )
    self.rootURL = standardizedRoot
    self.manifestURL = standardizedRoot.appendingPathComponent("database.manifest", isDirectory: false)
    self.pendingWALURL = standardizedRoot.appendingPathComponent("pending.wal", isDirectory: false)
    self.lockURL = standardizedRoot.appendingPathComponent("database.lock", isDirectory: false)
    self.digester = digester
    self.isClosed = false

    let acquiredInProcess = Self.lockedPaths.withLock { paths in
      paths.insert(standardizedRoot.path).inserted
    }
    guard acquiredInProcess else {
      throw DesignDatabaseError.persistence("The database is already open in this process.")
    }

    let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      Self.releaseInProcessLock(path: standardizedRoot.path)
      throw DesignDatabaseError.persistence("Unable to open the database lock file.")
    }
    guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
      Darwin.close(descriptor)
      Self.releaseInProcessLock(path: standardizedRoot.path)
      throw DesignDatabaseError.persistence("The database is already open by another process.")
    }
    self.lockDescriptor = descriptor
  }

  deinit {
    if lockDescriptor >= 0 {
      Darwin.lockf(lockDescriptor, F_ULOCK, 0)
      Darwin.close(lockDescriptor)
      Self.releaseInProcessLock(path: rootURL.path)
    }
  }

  public func load() async throws(DesignDatabaseError) -> DesignDatabaseImage? {
    try requireOpen()
    if FileManager.default.fileExists(atPath: pendingWALURL.path) {
      let envelope = try readEnvelope(at: pendingWALURL)
      do {
        try envelope.payload.write(to: manifestURL, options: .atomic)
        try synchronizeFile(at: manifestURL)
        try FileManager.default.removeItem(at: pendingWALURL)
        try synchronizeDirectory()
      } catch {
        throw .persistence("Recovered the manifest but could not remove the WAL: \(error)")
      }
    }
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
    do {
      return try JSONDecoder().decode(
        DesignDatabaseImage.self,
        from: Data(contentsOf: manifestURL, options: [.mappedIfSafe])
      )
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .corruption("Database manifest cannot be decoded: \(error)")
    }
  }

  public func persist(
    _ image: DesignDatabaseImage,
    publishing revision: DesignRevisionReference?
  ) async throws(DesignDatabaseError) {
    try requireOpen()
    if Task.isCancelled { throw .cancelled }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let payload = try encoder.encode(image)
      let digest = try digester.digest(data: payload, using: .sha256)
      let envelope = WriteAheadEnvelope(
        databaseID: image.databaseID,
        publishing: revision,
        payloadDigest: digest,
        payload: payload
      )
      try encoder.encode(envelope).write(to: pendingWALURL, options: .atomic)
      try synchronizeFile(at: pendingWALURL)
      try synchronizeDirectory()
      try payload.write(to: manifestURL, options: .atomic)
      try synchronizeFile(at: manifestURL)
      try synchronizeDirectory()
      try FileManager.default.removeItem(at: pendingWALURL)
      try synchronizeDirectory()
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .persistence(String(describing: error))
    }
  }

  public func close() async throws(DesignDatabaseError) {
    if isClosed { return }
    let unlockResult = Darwin.lockf(lockDescriptor, F_ULOCK, 0)
    let closeResult = Darwin.close(lockDescriptor)
    lockDescriptor = -1
    isClosed = true
    Self.releaseInProcessLock(path: rootURL.path)
    guard unlockResult == 0, closeResult == 0 else {
      throw .persistence("Unable to release the database lock cleanly.")
    }
  }

  private func readEnvelope(at url: URL) throws(DesignDatabaseError) -> WriteAheadEnvelope {
    do {
      let data = try Data(contentsOf: url, options: [.mappedIfSafe])
      let envelope = try JSONDecoder().decode(WriteAheadEnvelope.self, from: data)
      let actualDigest = try digester.digest(data: envelope.payload, using: .sha256)
      guard actualDigest == envelope.payloadDigest else {
        throw DesignDatabaseError.corruption("WAL payload digest mismatch.")
      }
      let image = try JSONDecoder().decode(DesignDatabaseImage.self, from: envelope.payload)
      guard image.databaseID == envelope.databaseID else {
        throw DesignDatabaseError.corruption("WAL database identity mismatch.")
      }
      if let publishing = envelope.publishing {
        guard
          publishing.databaseID == image.databaseID,
          image.revisions[publishing.revisionID] != nil
        else {
          throw DesignDatabaseError.corruption("WAL publication target is unavailable.")
        }
      }
      return envelope
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .corruption("WAL cannot be decoded: \(error)")
    }
  }

  private func requireOpen() throws(DesignDatabaseError) {
    if isClosed { throw .closed }
  }

  private func synchronizeFile(at url: URL) throws(DesignDatabaseError) {
    let descriptor = Darwin.open(url.path, O_RDONLY)
    guard descriptor >= 0 else {
      throw .persistence("Unable to open a persisted file for synchronization.")
    }
    let syncResult = Darwin.fsync(descriptor)
    let closeResult = Darwin.close(descriptor)
    guard syncResult == 0, closeResult == 0 else {
      throw .persistence("Unable to synchronize a persisted file.")
    }
  }

  private func synchronizeDirectory() throws(DesignDatabaseError) {
    let descriptor = Darwin.open(rootURL.path, O_RDONLY)
    guard descriptor >= 0 else {
      throw .persistence("Unable to open the database directory for synchronization.")
    }
    let syncResult = Darwin.fsync(descriptor)
    let closeResult = Darwin.close(descriptor)
    guard syncResult == 0, closeResult == 0 else {
      throw .persistence("Unable to synchronize the database directory.")
    }
  }

  private static func releaseInProcessLock(path: String) {
    _ = lockedPaths.withLock { paths in
      paths.remove(path)
    }
  }
}

private struct WriteAheadEnvelope: Sendable, Codable {
  let databaseID: DesignDatabaseID
  let publishing: DesignRevisionReference?
  let payloadDigest: ContentDigest
  let payload: Data
}
