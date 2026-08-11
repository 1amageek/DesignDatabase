public struct DesignDatabaseServiceConfiguration: Sendable, Hashable, Codable {
  public let maximumSessionCount: UInt64

  public init(maximumSessionCount: UInt64) throws(DesignDatabaseServiceError) {
    guard maximumSessionCount > 0 else {
      throw .sessionLimitReached(limit: 0)
    }
    self.maximumSessionCount = maximumSessionCount
  }

  private enum CodingKeys: String, CodingKey {
    case maximumSessionCount
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumSessionCount: container.decode(
          UInt64.self,
          forKey: .maximumSessionCount
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
