public struct DesignCanonicalKey: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public static let maximumByteCount = 4_096

  public let bytes: [UInt8]

  public init(bytes: [UInt8]) throws(DesignDatabaseError) {
    guard !bytes.isEmpty else {
      throw .invalidQuery("A canonical projection key must not be empty.")
    }
    guard bytes.count <= Self.maximumByteCount else {
      throw .invalidQuery(
        "A canonical projection key exceeds the maximum encoded byte count."
      )
    }
    self.bytes = bytes
  }

  public static func < (
    lhs: DesignCanonicalKey,
    rhs: DesignCanonicalKey
  ) -> Bool {
    lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
  }

  public func hasPrefix(_ prefix: DesignCanonicalKey) -> Bool {
    guard prefix.bytes.count <= bytes.count else { return false }
    return bytes.prefix(prefix.bytes.count).elementsEqual(prefix.bytes)
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case bytes
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let bytes = try container.decode([UInt8].self, forKey: .bytes)
    do {
      try self.init(bytes: bytes)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .bytes,
        in: container,
        debugDescription: String(describing: error)
      )
    }
  }
#endif
}
