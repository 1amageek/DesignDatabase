import CircuiteFoundation

public struct DesignDatabaseCreateRequest: Sendable, Hashable {
  public let locator: DesignDatabaseLocator
  public let databaseID: DesignDatabaseID
  public let genesisRevisionID: DesignRevisionID
  public let operationID: DesignDatabaseOperationID
  public let initialSchemaBundle: DesignSchemaBundle
  public let declaredFeatureCapabilities: DesignCapabilitySet
  public let requestDigest: ContentDigest

  public init(
    locator: DesignDatabaseLocator,
    databaseID: DesignDatabaseID,
    genesisRevisionID: DesignRevisionID,
    operationID: DesignDatabaseOperationID,
    initialSchemaBundle: DesignSchemaBundle,
    declaredFeatureCapabilities: DesignCapabilitySet,
    requestDigest: ContentDigest
  ) {
    self.locator = locator
    self.databaseID = databaseID
    self.genesisRevisionID = genesisRevisionID
    self.operationID = operationID
    self.initialSchemaBundle = initialSchemaBundle
    self.declaredFeatureCapabilities = declaredFeatureCapabilities
    self.requestDigest = requestDigest
  }
}
