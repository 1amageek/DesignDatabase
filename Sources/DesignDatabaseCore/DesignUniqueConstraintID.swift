import Foundation

public struct DesignUniqueConstraintID: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(rawValue, kind: "Unique constraint identifier")
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

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  public var description: String { rawValue }
}
