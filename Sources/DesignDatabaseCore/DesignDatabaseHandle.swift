import CircuiteFoundation

public protocol DesignDatabaseHandle: Sendable {
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var featureCapabilities: DesignCapabilitySet { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }
  var genesisRevision: DesignRevisionReference { get }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference

  func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> any DesignReadSnapshot

  func diff(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionDiff

  func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergeAssessment

  func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseError) -> DesignCommitResult

  func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitStatus

  func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateResult

  func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateStatus

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

  func close() async -> DesignDatabaseTermination
}
