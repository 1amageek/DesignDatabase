import CircuiteFoundation

public struct DesignDatabaseOpenRequest: Sendable, Hashable {
  public let locator: DesignDatabaseLocator
  public let expectedDatabaseID: DesignDatabaseID
  public let requiredFeatureCapabilities: DesignCapabilitySet
  public let requestedAuthorization: DesignDatabaseAuthorizationGrantSet

  public init(
    locator: DesignDatabaseLocator,
    expectedDatabaseID: DesignDatabaseID,
    requiredFeatureCapabilities: DesignCapabilitySet,
    requestedAuthorization: DesignDatabaseAuthorizationGrantSet
  ) {
    self.locator = locator
    self.expectedDatabaseID = expectedDatabaseID
    self.requiredFeatureCapabilities = requiredFeatureCapabilities
    self.requestedAuthorization = requestedAuthorization
  }
}
