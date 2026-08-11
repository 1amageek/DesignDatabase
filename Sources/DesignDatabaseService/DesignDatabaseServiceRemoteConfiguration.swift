public struct DesignDatabaseServiceRemoteConfiguration: Sendable, Hashable {
  public let wireCodecBudget: DesignDatabaseServiceWireCodecBudget
  public let queryPageCodecBudget: DesignDatabaseServiceQueryPageCodecBudget
  public let requestTimeout: Duration

  public init(
    wireCodecBudget: DesignDatabaseServiceWireCodecBudget,
    queryPageCodecBudget: DesignDatabaseServiceQueryPageCodecBudget,
    requestTimeout: Duration
  ) throws(DesignDatabaseServiceWireTransportError) {
    guard requestTimeout > .zero else {
      throw .invalidConfiguration(
        reason: "A remote service request timeout must be greater than zero."
      )
    }
    self.wireCodecBudget = wireCodecBudget
    self.queryPageCodecBudget = queryPageCodecBudget
    self.requestTimeout = requestTimeout
  }
}
