public struct DesignQueryExecutionPolicy: Sendable, Hashable, Codable {
  public let allowsFullScan: Bool
  public let maximumResultCount: UInt64

  public init(
    allowsFullScan: Bool = false,
    maximumResultCount: UInt64 = 100_000
  ) throws(DesignDatabaseError) {
    guard maximumResultCount > 0 else {
      throw DesignDatabaseError.resourceExhausted(limit: 0, requested: 0)
    }
    self.allowsFullScan = allowsFullScan
    self.maximumResultCount = maximumResultCount
  }
}
