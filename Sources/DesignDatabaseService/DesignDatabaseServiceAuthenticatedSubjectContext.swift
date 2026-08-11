import CircuiteFoundation

public struct DesignDatabaseServiceAuthenticatedSubjectContext:
  Sendable,
  Hashable
{
  public let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let serviceShutdownAuthorized: Bool

  public init(
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    serviceShutdownAuthorized: Bool = false
  ) {
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.serviceShutdownAuthorized = serviceShutdownAuthorized
  }
}
