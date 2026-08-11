public struct DesignDatabaseLocator: Sendable, Hashable, DesignDatabaseSerializable {
  public let namespace: String
  public let segments: [String]

  public init(
    namespace: String,
    segments: [String]
  ) throws(DesignDatabaseError) {
    guard Self.isCanonicalComponent(namespace) else {
      throw .invalidLocator(reason: "The namespace is not a canonical locator component.")
    }
    guard !segments.isEmpty, segments.count <= 16 else {
      throw .invalidLocator(reason: "A locator requires between 1 and 16 segments.")
    }
    guard segments.allSatisfy(Self.isCanonicalComponent) else {
      throw .invalidLocator(reason: "Every segment must be a canonical locator component.")
    }
    self.namespace = namespace
    self.segments = segments
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        namespace: container.decode(String.self, forKey: .namespace),
        segments: container.decode([String].self, forKey: .segments)
      )
    } catch let error as DesignDatabaseError {
      throw error
    }
  }
#endif

  private static func isCanonicalComponent(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 64 else { return false }
    guard let first = value.utf8.first,
          Self.isLowercaseLetter(first) || Self.isDigit(first) else {
      return false
    }
    guard let last = value.utf8.last,
          Self.isLowercaseLetter(last) || Self.isDigit(last) else {
      return false
    }
    return value.utf8.allSatisfy {
      Self.isLowercaseLetter($0) || Self.isDigit($0) || $0 == 45
    }
  }

  private static func isLowercaseLetter(_ byte: UInt8) -> Bool {
    byte >= 97 && byte <= 122
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    byte >= 48 && byte <= 57
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case namespace
    case segments
  }
#endif
}
