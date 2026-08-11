import CircuiteFoundation

public struct DesignDatabaseOperationReference:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public let databaseID: DesignDatabaseID
  public let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let operationID: DesignDatabaseOperationID

  public init(
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    operationID: DesignDatabaseOperationID
  ) {
    self.databaseID = databaseID
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.operationID = operationID
  }
}
