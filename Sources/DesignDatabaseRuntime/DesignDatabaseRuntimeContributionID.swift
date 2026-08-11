public struct DesignDatabaseRuntimeContributionID: Sendable, Hashable, Codable, Comparable {
  public let rawValue: String

  public init(_ rawValue: String) throws(DesignDatabaseRuntimeError) {
    let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2,
          components.allSatisfy(Self.isCanonicalComponent),
          rawValue.utf8.count <= 255 else {
      throw .invalidContributionIdentifier(rawValue)
    }
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      try self.init(container.decode(String.self))
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public static func < (
    lhs: DesignDatabaseRuntimeContributionID,
    rhs: DesignDatabaseRuntimeContributionID
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  private static func isCanonicalComponent(_ component: Substring) -> Bool {
    guard !component.isEmpty, component.utf8.count <= 63 else { return false }
    guard let first = component.utf8.first,
          Self.isLowercaseLetter(first) || Self.isDigit(first) else {
      return false
    }
    guard let last = component.utf8.last,
          Self.isLowercaseLetter(last) || Self.isDigit(last) else {
      return false
    }
    return component.utf8.allSatisfy {
      Self.isLowercaseLetter($0) || Self.isDigit($0) || $0 == 45
    }
  }

  private static func isLowercaseLetter(_ byte: UInt8) -> Bool {
    byte >= 97 && byte <= 122
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    byte >= 48 && byte <= 57
  }
}
