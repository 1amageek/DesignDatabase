import CircuiteFoundation

public struct DesignServiceNegotiationRequest: Sendable, Hashable, Codable {
  public let requiredSchemas: [DesignSchemaRequirement]
  public let requiredCapabilities: [DesignCapabilityRequirement]

  public init(
    requiredSchemas: [DesignSchemaRequirement],
    requiredCapabilities: [DesignCapabilityRequirement]
  ) {
    self.requiredSchemas = requiredSchemas
    self.requiredCapabilities = requiredCapabilities
  }
}
