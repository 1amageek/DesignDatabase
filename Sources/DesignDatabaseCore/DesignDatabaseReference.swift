import CircuiteFoundation

public protocol DesignDatabaseReference: Sendable {
  var databaseID: DesignDatabaseID { get }
  var capabilities: DesignCapabilitySet { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference

  func snapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceReadSnapshot

  func manifest(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceRevisionManifest

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

  func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission

  func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission

  func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionStatus

  func close() async throws(DesignDatabaseError)
}
