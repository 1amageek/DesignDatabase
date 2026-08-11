import Database

public protocol DesignDatabaseRuntimePhysicalWriteReclaimer: Sendable {
  var storageType: String { get }

  func deleteImmutableWrite(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    from transaction: any DatabaseTransactionWriting
  ) async throws(DesignDatabaseRuntimePhysicalWriteReclaimerError)
}
