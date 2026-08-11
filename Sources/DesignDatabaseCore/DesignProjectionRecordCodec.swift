import CircuiteFoundation

enum DesignProjectionRecordCodec {
  static func append(_ value: UInt8, to bytes: inout [UInt8]) {
    bytes.append(value)
  }

  static func append(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  static func append(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  static func append(_ value: UInt64, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 56))
    bytes.append(UInt8(truncatingIfNeeded: value >> 48))
    bytes.append(UInt8(truncatingIfNeeded: value >> 40))
    bytes.append(UInt8(truncatingIfNeeded: value >> 32))
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  static func append(
    _ value: String,
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseError) {
    try append(Array(value.utf8), to: &bytes)
  }

  static func append(
    _ value: [UInt8],
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseError) {
    guard let count = UInt32(exactly: value.count) else {
      throw .invalidMutationPlan(
        reason: "A projection record field exceeds the canonical byte limit."
      )
    }
    append(count, to: &bytes)
    bytes.append(contentsOf: value)
  }

  static func append(
    _ digest: ContentDigest,
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseError) {
    try append(digest.algorithm.rawValue, to: &bytes)
    try append(digest.hexadecimalValue, to: &bytes)
  }

  static func append(
    _ target: DesignRelationOccurrenceTarget,
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseError) {
    switch target {
    case .local(let entityID):
      append(UInt8(0), to: &bytes)
      append(entityID.rawValue, to: &bytes)
    case .exact(let reference):
      append(UInt8(1), to: &bytes)
      append(reference.revision.databaseID.high, to: &bytes)
      append(reference.revision.databaseID.low, to: &bytes)
      append(reference.revision.revisionID.high, to: &bytes)
      append(reference.revision.revisionID.low, to: &bytes)
      try append(reference.facetID.rawValue, to: &bytes)
      try append(reference.kindID.rawValue, to: &bytes)
      append(reference.entityID.rawValue, to: &bytes)
    }
  }

  struct Reader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func readUInt8() throws(DesignDatabaseError) -> UInt8 {
      guard offset < bytes.count else {
        throw .corruption("A projection record ended before its declared fields.")
      }
      defer { offset += 1 }
      return bytes[offset]
    }

    mutating func readUInt16() throws(DesignDatabaseError) -> UInt16 {
      let high = UInt16(try readUInt8())
      let low = UInt16(try readUInt8())
      return (high << 8) | low
    }

    mutating func readUInt32() throws(DesignDatabaseError) -> UInt32 {
      var value: UInt32 = 0
      for _ in 0..<4 {
        value = (value << 8) | UInt32(try readUInt8())
      }
      return value
    }

    mutating func readUInt64() throws(DesignDatabaseError) -> UInt64 {
      var value: UInt64 = 0
      for _ in 0..<8 {
        value = (value << 8) | UInt64(try readUInt8())
      }
      return value
    }

    mutating func readBytes() throws(DesignDatabaseError) -> [UInt8] {
      let count = try readUInt32()
      guard let countValue = Int(exactly: count),
            countValue <= bytes.count - offset else {
        throw .corruption("A projection record field exceeds its payload.")
      }
      defer { offset += countValue }
      return Array(bytes[offset..<(offset + countValue)])
    }

    mutating func readString() throws(DesignDatabaseError) -> String {
      let value = try readBytes()
      let string = String(decoding: value, as: UTF8.self)
      guard Array(string.utf8) == value else {
        throw .corruption("A projection record string is not valid UTF-8.")
      }
      return string
    }

    mutating func readDigest() throws(DesignDatabaseError) -> ContentDigest {
      do {
        return try ContentDigest(
          algorithm: ContentDigestAlgorithm(rawValue: readString()),
          hexadecimalValue: readString()
        )
      } catch let error as DesignDatabaseError {
        throw error
      } catch {
        throw .corruption("A projection record content digest is invalid.")
      }
    }

    mutating func readTarget()
      throws(DesignDatabaseError) -> DesignRelationOccurrenceTarget
    {
      switch try readUInt8() {
      case 0:
        do {
          return .local(try DesignEntityID(rawValue: readUInt64()))
        } catch {
          throw .corruption("A local relation target identity is invalid.")
        }
      case 1:
        do {
          let databaseID = try DesignDatabaseID(
            high: readUInt64(),
            low: readUInt64()
          )
          let revisionID = DesignRevisionID(
            high: try readUInt64(),
            low: try readUInt64()
          )
          return .exact(
            DesignEntityReference(
              revision: DesignRevisionReference(
                databaseID: databaseID,
                revisionID: revisionID
              ),
              facetID: try DesignFacetID(rawValue: readString()),
              kindID: try DesignEntityKindID(rawValue: readString()),
              entityID: try DesignEntityID(rawValue: readUInt64())
            )
          )
        } catch {
          throw .corruption("An exact relation target identity is invalid.")
        }
      default:
        throw .corruption("A projection record contains an unknown target kind.")
      }
    }

    mutating func requireExhausted() throws(DesignDatabaseError) {
      guard offset == bytes.count else {
        throw .corruption("A projection record contains trailing bytes.")
      }
    }
  }
}
