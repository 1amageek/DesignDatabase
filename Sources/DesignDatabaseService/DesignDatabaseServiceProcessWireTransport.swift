import Foundation

public actor DesignDatabaseServiceProcessWireTransport:
  DesignDatabaseServiceWireTransport
{
  private enum TimedRead: Sendable {
    case frame([UInt8])
  }

  private let process: Process
  private let requestHandle: FileHandle
  private let responseHandle: FileHandle
  private var responseIterator: FileHandle.AsyncBytes.Iterator
  private let maximumFrameByteCount: UInt64
  private let closeGracePeriod: Duration
  private var exchangeIsAvailable = true
  private var exchangeWaiters: [CheckedContinuation<Void, Never>] = []
  private var isClosed = false
  private var deadlineExpired = false

  public init(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    maximumFrameByteCount: UInt64,
    closeGracePeriod: Duration = .seconds(2)
  ) throws(DesignDatabaseServiceWireTransportError) {
    guard maximumFrameByteCount > 0 else {
      throw .invalidConfiguration(
        reason: "A process transport frame budget must be greater than zero."
      )
    }
    guard closeGracePeriod > .zero else {
      throw .invalidConfiguration(
        reason: "A process transport close grace period must be greater than zero."
      )
    }
    let process = Process()
    let requestPipe = Pipe()
    let responsePipe = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    if let environment { process.environment = environment }
    process.standardInput = requestPipe
    process.standardOutput = responsePipe
    process.standardError = FileHandle.standardError
    do {
      try process.run()
      try requestPipe.fileHandleForReading.close()
      try responsePipe.fileHandleForWriting.close()
    } catch {
      if process.isRunning { process.terminate() }
      throw .inputOutputFailure(reason: String(describing: error))
    }
    self.process = process
    self.requestHandle = requestPipe.fileHandleForWriting
    self.responseHandle = responsePipe.fileHandleForReading
    self.responseIterator = responsePipe.fileHandleForReading.bytes
      .makeAsyncIterator()
    self.maximumFrameByteCount = maximumFrameByteCount
    self.closeGracePeriod = closeGracePeriod
  }

  public func exchange(
    _ requestFrame: [UInt8],
    timeout: Duration
  ) async throws(DesignDatabaseServiceWireTransportError) -> [UInt8] {
    guard timeout > .zero else { throw .deadlineExceeded }
    await acquireExchange()
    defer { releaseExchange() }
    guard !isClosed, process.isRunning else { throw .closed }
    let encoded = try DesignDatabaseServiceLengthPrefixedFrameIO.encoded(
      requestFrame,
      maximumFrameByteCount: maximumFrameByteCount
    )
    do {
      try requestHandle.write(contentsOf: encoded)
    } catch {
      let primaryReason = String(describing: error)
      do {
        try closeResources()
      } catch let closeError {
        throw .inputOutputFailure(
          reason: "Process request write failed with \(primaryReason); cleanup also failed with \(closeError)."
        )
      }
      throw .inputOutputFailure(reason: primaryReason)
    }

    do {
      return try await withThrowingTaskGroup(
        of: TimedRead.self,
        returning: [UInt8].self
      ) { group in
        group.addTask { [self] in
          .frame(try await readResponseFrame())
        }
        group.addTask { [self] in
          try await ContinuousClock().sleep(for: timeout)
          try await terminateForDeadline()
          throw DesignDatabaseServiceWireTransportError.deadlineExceeded
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
          throw DesignDatabaseServiceWireTransportError.closed
        }
        switch result {
        case .frame(let frame):
          return frame
        }
      }
    } catch let error as DesignDatabaseServiceWireTransportError {
      throw error
    } catch {
      let primaryReason = String(describing: error)
      do {
        try closeResources()
      } catch let closeError {
        throw .inputOutputFailure(
          reason: "Process response read failed with \(primaryReason); cleanup also failed with \(closeError)."
        )
      }
      throw .inputOutputFailure(reason: primaryReason)
    }
  }

  public func close() async throws(DesignDatabaseServiceWireTransportError) {
    guard !isClosed else { return }
    isClosed = true
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: closeGracePeriod)
    while process.isRunning, clock.now < deadline {
      do {
        try await clock.sleep(for: .milliseconds(10))
      } catch {
        failures.append("graceful close wait: \(error)")
        break
      }
    }
    if process.isRunning {
      process.terminate()
      failures.append(
        "child process did not exit within \(closeGracePeriod)"
      )
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    guard failures.isEmpty else {
      throw .inputOutputFailure(reason: failures.joined(separator: "; "))
    }
  }

  private func closeResources()
    throws(DesignDatabaseServiceWireTransportError) {
    guard !isClosed else { return }
    isClosed = true
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    if process.isRunning { process.terminate() }
    guard failures.isEmpty else {
      throw .inputOutputFailure(reason: failures.joined(separator: "; "))
    }
  }

  private func acquireExchange() async {
    if exchangeIsAvailable {
      exchangeIsAvailable = false
      return
    }
    await withCheckedContinuation { continuation in
      exchangeWaiters.append(continuation)
    }
  }

  private func releaseExchange() {
    guard !exchangeWaiters.isEmpty else {
      exchangeIsAvailable = true
      return
    }
    let waiter = exchangeWaiters.removeFirst()
    waiter.resume()
  }

  private func readResponseFrame()
    async throws(DesignDatabaseServiceWireTransportError) -> [UInt8] {
    do {
      var iterator = responseIterator
      guard let frame = try await DesignDatabaseServiceLengthPrefixedFrameIO.read(
        from: &iterator,
        maximumFrameByteCount: maximumFrameByteCount
      ) else {
        throw DesignDatabaseServiceWireTransportError.closed
      }
      responseIterator = iterator
      return frame
    } catch let error as DesignDatabaseServiceWireTransportError {
      if deadlineExpired { throw .deadlineExceeded }
      throw error
    } catch {
      if deadlineExpired { throw .deadlineExceeded }
      throw .inputOutputFailure(reason: String(describing: error))
    }
  }

  private func terminateForDeadline()
    throws(DesignDatabaseServiceWireTransportError) {
    guard !isClosed else { return }
    deadlineExpired = true
    isClosed = true
    if process.isRunning { process.terminate() }
    var failures: [String] = []
    do {
      try requestHandle.close()
    } catch {
      failures.append("request close: \(error)")
    }
    do {
      try responseHandle.close()
    } catch {
      failures.append("response close: \(error)")
    }
    guard failures.isEmpty else {
      throw .inputOutputFailure(
        reason: "The request deadline expired and forced cleanup failed: \(failures.joined(separator: "; "))."
      )
    }
  }
}
