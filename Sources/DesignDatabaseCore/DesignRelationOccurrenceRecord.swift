import CircuiteFoundation

public struct DesignRelationOccurrenceRecord:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable
{
  public let projectionFamily: DesignProjectionFamily
  public let occurrenceID: DesignRelationOccurrenceID
  public let ownerEntityID: DesignEntityID
  public let relationKindID: DesignRelationKindID
  public let target: DesignRelationOccurrenceTarget
  public let orderKey: DesignCanonicalKey
  public let attributesDigest: ContentDigest?

  public init(
    projectionFamily: DesignProjectionFamily,
    occurrenceID: DesignRelationOccurrenceID,
    ownerEntityID: DesignEntityID,
    relationKindID: DesignRelationKindID,
    target: DesignRelationOccurrenceTarget,
    orderKey: DesignCanonicalKey,
    attributesDigest: ContentDigest?
  ) throws(DesignDatabaseError) {
    guard Self.supportedFamilies.contains(projectionFamily) else {
      throw .invalidMutationPlan(
        reason: "A relation occurrence targets a non-relational projection family."
      )
    }
    self.projectionFamily = projectionFamily
    self.occurrenceID = occurrenceID
    self.ownerEntityID = ownerEntityID
    self.relationKindID = relationKindID
    self.target = target
    self.orderKey = orderKey
    self.attributesDigest = attributesDigest
  }

  public init(
    projectionEntry: DesignProjectionEntry
  ) throws(DesignDatabaseError) {
    var valueReader = DesignProjectionRecordCodec.Reader(projectionEntry.value)
    do {
      guard try valueReader.readUInt16() == 1 else {
        throw DesignDatabaseError.corruption(
          "A relation-occurrence projection record uses an unsupported codec version."
        )
      }
      guard let family = DesignProjectionFamily(
        rawValue: try valueReader.readString()
      ) else {
        throw DesignDatabaseError.corruption(
          "A relation-occurrence projection record has an unknown family."
        )
      }
      let occurrenceID = try DesignRelationOccurrenceID(
        rawValue: valueReader.readUInt64()
      )
      let ownerEntityID = try DesignEntityID(
        rawValue: valueReader.readUInt64()
      )
      let relationKindID = try DesignRelationKindID(
        rawValue: valueReader.readString()
      )
      let target = try valueReader.readTarget()
      let orderKey = try DesignCanonicalKey(bytes: valueReader.readBytes())
      let attributesDigest: ContentDigest?
      switch try valueReader.readUInt8() {
      case 0:
        attributesDigest = nil
      case 1:
        attributesDigest = try valueReader.readDigest()
      default:
        throw DesignDatabaseError.corruption(
          "A relation-occurrence projection record has an invalid attributes marker."
        )
      }
      try valueReader.requireExhausted()
      try self.init(
        projectionFamily: family,
        occurrenceID: occurrenceID,
        ownerEntityID: ownerEntityID,
        relationKindID: relationKindID,
        target: target,
        orderKey: orderKey,
        attributesDigest: attributesDigest
      )
      guard try projectionEntries().contains(projectionEntry) else {
        throw DesignDatabaseError.corruption(
          "A relation-occurrence projection key does not match its value."
        )
      }
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .corruption(
        "A relation-occurrence projection record is malformed."
      )
    }
  }

  public func projectionEntries()
    throws(DesignDatabaseError) -> [DesignProjectionEntry]
  {
    [
      try projectionEntry(direction: 0, matched: .local(ownerEntityID)),
      try projectionEntry(direction: 1, matched: target),
    ]
  }

  public static func < (
    lhs: DesignRelationOccurrenceRecord,
    rhs: DesignRelationOccurrenceRecord
  ) -> Bool {
    lhs.occurrenceID < rhs.occurrenceID
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        projectionFamily: container.decode(
          DesignProjectionFamily.self,
          forKey: .projectionFamily
        ),
        occurrenceID: container.decode(
          DesignRelationOccurrenceID.self,
          forKey: .occurrenceID
        ),
        ownerEntityID: container.decode(
          DesignEntityID.self,
          forKey: .ownerEntityID
        ),
        relationKindID: container.decode(
          DesignRelationKindID.self,
          forKey: .relationKindID
        ),
        target: container.decode(
          DesignRelationOccurrenceTarget.self,
          forKey: .target
        ),
        orderKey: container.decode(
          DesignCanonicalKey.self,
          forKey: .orderKey
        ),
        attributesDigest: container.decodeIfPresent(
          ContentDigest.self,
          forKey: .attributesDigest
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif

  private func projectionEntry(
    direction: UInt8,
    matched: DesignRelationOccurrenceTarget
  ) throws(DesignDatabaseError) -> DesignProjectionEntry {
    var key: [UInt8] = []
    DesignProjectionRecordCodec.append(UInt16(1), to: &key)
    DesignProjectionRecordCodec.append(direction, to: &key)
    try DesignProjectionRecordCodec.append(matched, to: &key)
    try DesignProjectionRecordCodec.append(relationKindID.rawValue, to: &key)
    DesignProjectionRecordCodec.append(ownerEntityID.rawValue, to: &key)
    try DesignProjectionRecordCodec.append(orderKey.bytes, to: &key)
    try DesignProjectionRecordCodec.append(target, to: &key)
    DesignProjectionRecordCodec.append(occurrenceID.rawValue, to: &key)

    var value: [UInt8] = []
    DesignProjectionRecordCodec.append(UInt16(1), to: &value)
    try DesignProjectionRecordCodec.append(projectionFamily.rawValue, to: &value)
    DesignProjectionRecordCodec.append(occurrenceID.rawValue, to: &value)
    DesignProjectionRecordCodec.append(ownerEntityID.rawValue, to: &value)
    try DesignProjectionRecordCodec.append(relationKindID.rawValue, to: &value)
    try DesignProjectionRecordCodec.append(target, to: &value)
    try DesignProjectionRecordCodec.append(orderKey.bytes, to: &value)
    DesignProjectionRecordCodec.append(
      attributesDigest == nil ? UInt8(0) : UInt8(1),
      to: &value
    )
    if let attributesDigest {
      try DesignProjectionRecordCodec.append(attributesDigest, to: &value)
    }
    return try DesignProjectionEntry(
      key: DesignCanonicalKey(bytes: key),
      value: value
    )
  }

  private static let supportedFamilies: Set<DesignProjectionFamily> = [
    .hierarchy,
    .connectivity,
    .crossFacet,
    .dependency,
  ]

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case projectionFamily
    case occurrenceID
    case ownerEntityID
    case relationKindID
    case target
    case orderKey
    case attributesDigest
  }
#endif
}
