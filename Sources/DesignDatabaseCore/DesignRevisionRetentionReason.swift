public struct DesignRevisionRetentionReason:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(rawValue, kind: "Design revision retention reason")
    self.rawValue = rawValue
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
#endif

  public var description: String { rawValue }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
