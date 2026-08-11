public struct DesignProjectionEntry: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public static let maximumValueByteCount = 1_048_576

  public let key: DesignCanonicalKey
  public let value: [UInt8]

  public init(
    key: DesignCanonicalKey,
    value: [UInt8]
  ) throws(DesignDatabaseError) {
    guard !value.isEmpty else {
      throw .invalidQuery("A semantic projection value must not be empty.")
    }
    guard value.count <= Self.maximumValueByteCount else {
      throw .invalidQuery(
        "A semantic projection value exceeds the maximum encoded byte count."
      )
    }
    self.key = key
    self.value = value
  }

  public static func < (
    lhs: DesignProjectionEntry,
    rhs: DesignProjectionEntry
  ) -> Bool {
    lhs.key < rhs.key
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case key
    case value
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let key = try container.decode(DesignCanonicalKey.self, forKey: .key)
    let value = try container.decode([UInt8].self, forKey: .value)
    do {
      try self.init(key: key, value: value)
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .value,
        in: container,
        debugDescription: String(describing: error)
      )
    }
  }
#endif
}
