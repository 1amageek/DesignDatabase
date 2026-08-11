public struct DesignDependencyID:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable,
  CustomStringConvertible
{
  public let rawValue: String

  public var description: String { rawValue }

  public init(rawValue: String) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(
      rawValue,
      kind: "Design dependency identifier"
    )
    self.rawValue = rawValue
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      try self.init(rawValue: container.decode(String.self))
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: String(describing: error)
      )
    }
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
#endif

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
