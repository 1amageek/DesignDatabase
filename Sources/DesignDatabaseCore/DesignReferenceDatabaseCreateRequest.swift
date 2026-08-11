import CircuiteFoundation

public struct DesignReferenceDatabaseCreateRequest: Sendable {
  public let databaseID: DesignDatabaseID?
  public let schemas: [DesignFacetSchema]
  public let capabilities: DesignCapabilitySet
  public let validators: [any DesignFacetValidating]

  public init(
    databaseID: DesignDatabaseID? = nil,
    schemas: [DesignFacetSchema],
    capabilities: DesignCapabilitySet,
    validators: [any DesignFacetValidating] = []
  ) {
    self.databaseID = databaseID
    self.schemas = schemas
    self.capabilities = capabilities
    self.validators = validators
  }
}
