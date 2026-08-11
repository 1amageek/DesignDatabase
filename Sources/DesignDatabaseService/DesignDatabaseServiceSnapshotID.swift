public struct DesignDatabaseServiceSnapshotID:
  Sendable,
  Hashable,
  Codable,
  Comparable
{
  public let rawValue: UInt64

  public init(rawValue: UInt64) throws(DesignDatabaseServiceError) {
    guard rawValue > 0 else { throw .identifierSpaceExhausted }
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      try self.init(rawValue: container.decode(UInt64.self))
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: String(describing: error)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
