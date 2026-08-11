import CircuiteFoundation

public protocol DesignDatabaseMaintenanceHandle: Sendable {
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }

  func abandonCommit(
    _ request: DesignCommitAbandonmentRequest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentResult

  func commitAbandonmentStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentStatus
}
