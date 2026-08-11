public struct DesignQueryBudget: Sendable, Hashable, DesignDatabaseSerializable {
  public let maximumResultCount: UInt64
  public let maximumNodeFetchCount: UInt64
  public let maximumEncodedReadByteCount: UInt64
  public let maximumDecodedByteCount: UInt64
  public let maximumOutputByteCount: UInt64
  public let maximumWorkCount: UInt64

  public init(
    maximumResultCount: UInt64,
    maximumNodeFetchCount: UInt64,
    maximumEncodedReadByteCount: UInt64,
    maximumDecodedByteCount: UInt64,
    maximumOutputByteCount: UInt64,
    maximumWorkCount: UInt64
  ) throws(DesignDatabaseError) {
    let values = [
      maximumResultCount,
      maximumNodeFetchCount,
      maximumEncodedReadByteCount,
      maximumDecodedByteCount,
      maximumOutputByteCount,
      maximumWorkCount,
    ]
    guard values.allSatisfy({ $0 > 0 }) else {
      throw .invalidQuery("Every semantic query budget must be greater than zero.")
    }
    self.maximumResultCount = maximumResultCount
    self.maximumNodeFetchCount = maximumNodeFetchCount
    self.maximumEncodedReadByteCount = maximumEncodedReadByteCount
    self.maximumDecodedByteCount = maximumDecodedByteCount
    self.maximumOutputByteCount = maximumOutputByteCount
    self.maximumWorkCount = maximumWorkCount
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case maximumResultCount
    case maximumNodeFetchCount
    case maximumEncodedReadByteCount
    case maximumDecodedByteCount
    case maximumOutputByteCount
    case maximumWorkCount
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumResultCount: container.decode(
          UInt64.self,
          forKey: .maximumResultCount
        ),
        maximumNodeFetchCount: container.decode(
          UInt64.self,
          forKey: .maximumNodeFetchCount
        ),
        maximumEncodedReadByteCount: container.decode(
          UInt64.self,
          forKey: .maximumEncodedReadByteCount
        ),
        maximumDecodedByteCount: container.decode(
          UInt64.self,
          forKey: .maximumDecodedByteCount
        ),
        maximumOutputByteCount: container.decode(
          UInt64.self,
          forKey: .maximumOutputByteCount
        ),
        maximumWorkCount: container.decode(
          UInt64.self,
          forKey: .maximumWorkCount
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
#endif
}
