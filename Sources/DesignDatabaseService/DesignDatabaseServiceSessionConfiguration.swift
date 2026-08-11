public struct DesignDatabaseServiceSessionConfiguration: Sendable, Hashable, Codable {
  public let leaseDuration: Duration
  public let maximumInFlightOperationCount: UInt64

  public init(
    leaseDuration: Duration,
    maximumInFlightOperationCount: UInt64
  ) throws(DesignDatabaseServiceError) {
    guard leaseDuration > .zero else { throw .leaseExpired }
    guard maximumInFlightOperationCount > 0 else {
      throw .backpressure(limit: 0)
    }
    self.leaseDuration = leaseDuration
    self.maximumInFlightOperationCount = maximumInFlightOperationCount
  }

  private enum CodingKeys: String, CodingKey {
    case leaseDuration
    case maximumInFlightOperationCount
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        leaseDuration: container.decode(
          Duration.self,
          forKey: .leaseDuration
        ),
        maximumInFlightOperationCount: container.decode(
          UInt64.self,
          forKey: .maximumInFlightOperationCount
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
}
