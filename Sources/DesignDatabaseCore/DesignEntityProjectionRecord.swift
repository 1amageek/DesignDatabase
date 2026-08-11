import CircuiteFoundation

public struct DesignEntityProjectionRecord:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable
{
  public let entityID: DesignEntityID
  public let facetID: DesignFacetID
  public let kindID: DesignEntityKindID
  public let contentDigest: ContentDigest

  public init(
    entityID: DesignEntityID,
    facetID: DesignFacetID,
    kindID: DesignEntityKindID,
    contentDigest: ContentDigest
  ) {
    self.entityID = entityID
    self.facetID = facetID
    self.kindID = kindID
    self.contentDigest = contentDigest
  }

  public init(
    projectionEntry: DesignProjectionEntry
  ) throws(DesignDatabaseError) {
    var keyReader = DesignProjectionRecordCodec.Reader(projectionEntry.key.bytes)
    var valueReader = DesignProjectionRecordCodec.Reader(projectionEntry.value)
    do {
      guard try keyReader.readUInt16() == 1,
            try valueReader.readUInt16() == 1 else {
        throw DesignDatabaseError.corruption(
          "An entity projection record uses an unsupported codec version."
        )
      }
      let entityID = try DesignEntityID(rawValue: keyReader.readUInt64())
      try keyReader.requireExhausted()
      self.init(
        entityID: entityID,
        facetID: try DesignFacetID(rawValue: valueReader.readString()),
        kindID: try DesignEntityKindID(rawValue: valueReader.readString()),
        contentDigest: try valueReader.readDigest()
      )
      try valueReader.requireExhausted()
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .corruption("An entity projection record is malformed.")
    }
  }

  public func projectionEntry() throws(DesignDatabaseError) -> DesignProjectionEntry {
    var key: [UInt8] = []
    DesignProjectionRecordCodec.append(UInt16(1), to: &key)
    DesignProjectionRecordCodec.append(entityID.rawValue, to: &key)
    var value: [UInt8] = []
    DesignProjectionRecordCodec.append(UInt16(1), to: &value)
    try DesignProjectionRecordCodec.append(facetID.rawValue, to: &value)
    try DesignProjectionRecordCodec.append(kindID.rawValue, to: &value)
    try DesignProjectionRecordCodec.append(contentDigest, to: &value)
    return try DesignProjectionEntry(
      key: DesignCanonicalKey(bytes: key),
      value: value
    )
  }

  public static func < (
    lhs: DesignEntityProjectionRecord,
    rhs: DesignEntityProjectionRecord
  ) -> Bool {
    lhs.entityID < rhs.entityID
  }
}
