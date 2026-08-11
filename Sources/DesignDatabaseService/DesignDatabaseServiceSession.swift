import CircuiteFoundation
import DesignDatabaseCore

public protocol DesignDatabaseServiceSession: Sendable {
  var id: DesignDatabaseServiceSessionID { get }
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var featureCapabilities: DesignCapabilitySet { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }
  var genesisRevision: DesignRevisionReference { get }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionReference

  func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseServiceError)
    -> DesignDatabaseServiceSnapshotDescriptor

  func closeSnapshot(
    _ snapshotID: DesignDatabaseServiceSnapshotID
  ) async throws(DesignDatabaseServiceError) -> DesignSnapshotTermination

  func query(
    snapshotID: DesignDatabaseServiceSnapshotID,
    request: DesignQueryRequest
  ) async throws(DesignDatabaseServiceError) -> DesignQueryPage

  func diff(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionDiff

  func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseServiceError) -> DesignDisjointMergeAssessment

  func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseServiceError) -> DesignDisjointMergePublicationResult

  func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignDisjointMergePublicationStatus

  func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseServiceError) -> DesignCommitResult

  func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignCommitStatus

  func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateResult

  func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateStatus

  func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission

  func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission

  func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionStatus

}
