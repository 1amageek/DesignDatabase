public struct DesignReferenceName: Sendable, Hashable, Codable, Comparable {
  public let rawValue: String

  public init(rawValue: String) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(rawValue, kind: "Design reference name")
    guard !rawValue.hasPrefix("/"), !rawValue.hasSuffix("/"), !rawValue.contains("//") else {
      throw DesignDatabaseError.invalidToken(kind: "Design reference name", value: rawValue)
    }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  private init(uncheckedRawValue: String) {
    self.rawValue = uncheckedRawValue
  }

  public static let main = Self(uncheckedRawValue: "main")

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
