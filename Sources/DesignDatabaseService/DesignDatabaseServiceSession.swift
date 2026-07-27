import CircuiteFoundation
import DesignDatabaseCore

public actor DesignDatabaseServiceSession {
  public nonisolated let databaseID: DesignDatabaseID

  private let database: any DesignDatabase
  private let clock: ContinuousClock
  private let expiresAt: ContinuousClock.Instant
  private var isClosed: Bool

  public init(
    database: any DesignDatabase,
    leaseDuration: Duration
  ) throws(DesignDatabaseError) {
    guard leaseDuration > .zero else {
      throw DesignDatabaseError.invalidQuery("Session lease duration must be positive.")
    }
    let clock = ContinuousClock()
    self.databaseID = database.databaseID
    self.database = database
    self.clock = clock
    self.expiresAt = clock.now.advanced(by: leaseDuration)
    self.isClosed = false
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
    try requireActive()
    return try await database.resolve(selector)
  }

  public func query(
    revision: DesignRevisionReference,
    query: DesignQuery
  ) async throws(DesignDatabaseError) -> DesignQueryResult {
    try requireActive()
    let snapshot = try await database.snapshot(at: revision)
    return try snapshot.execute(query)
  }

  public func manifest(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignRevisionManifest {
    try requireActive()
    return try await database.manifest(at: revision)
  }

  public func apply(
    _ batch: DesignMutationBatch,
    from base: DesignRevisionReference,
    options: DesignTransactionOptions
  ) async throws(DesignDatabaseError) -> DesignTransactionResult<Void> {
    try requireActive()
    return try await database.withTransaction(
      from: base,
      options: options,
      { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> Void in
        try transaction.apply(batch)
      }
    )
  }

  public func shutdown() {
    isClosed = true
  }

  private func requireActive() throws(DesignDatabaseError) {
    guard !isClosed, clock.now < expiresAt else { throw .closed }
  }
}
