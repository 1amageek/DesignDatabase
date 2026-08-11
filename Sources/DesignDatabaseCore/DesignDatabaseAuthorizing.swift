import CircuiteFoundation

public protocol DesignDatabaseAuthorizing: Sendable {
  func authorizeRequestedGrants(
    _ requestedGrants: DesignDatabaseAuthorizationGrantSet,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError) -> DesignDatabaseAuthorizationGrantSet

  func authorize(
    _ grant: DesignDatabaseAuthorizationGrant,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError)
}
