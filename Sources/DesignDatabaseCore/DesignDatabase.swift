import CircuiteFoundation

public protocol DesignDatabase: Sendable {
  var databaseID: DesignDatabaseID { get }
  var capabilities: DesignCapabilitySet { get }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference

  func snapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReadSnapshot

  func manifest(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignRevisionManifest

  func withTransaction<Result: Sendable>(
    from base: DesignRevisionReference,
    options: DesignTransactionOptions,
    _ body: @Sendable (inout DesignTransaction) throws(DesignDatabaseError) -> Result
  ) async throws(DesignDatabaseError) -> DesignTransactionResult<Result>

  func compareAndSetReference(
    _ name: DesignReferenceName,
    expected: DesignRevisionReference?,
    desired: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdate

  func close() async throws(DesignDatabaseError)
}
