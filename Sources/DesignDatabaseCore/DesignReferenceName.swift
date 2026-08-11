public struct DesignReferenceName: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let rawValue: String

  public init(rawValue: String) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(rawValue, kind: "Design reference name")
    guard !rawValue.hasPrefix("/"),
          !rawValue.hasSuffix("/"),
          !Self.containsRepeatedSeparator(rawValue) else {
      throw DesignDatabaseError.invalidToken(kind: "Design reference name", value: rawValue)
    }
    self.rawValue = rawValue
  }

  private static func containsRepeatedSeparator(_ value: String) -> Bool {
    var previousWasSeparator = false
    for byte in value.utf8 {
      let isSeparator = byte == 47
      if previousWasSeparator && isSeparator {
        return true
      }
      previousWasSeparator = isSeparator
    }
    return false
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

  private init(uncheckedRawValue: String) {
    self.rawValue = uncheckedRawValue
  }

  public static let main = Self(uncheckedRawValue: "main")

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
