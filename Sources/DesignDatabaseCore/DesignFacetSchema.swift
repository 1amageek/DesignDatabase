import CircuiteFoundation

public struct DesignFacetSchema: Sendable, Hashable, DesignDatabaseSerializable {
  public let descriptor: DesignSchemaDescriptor
  public let entities: [DesignEntitySchema]
  public let indexes: Set<DesignIndexKind>

  public var facetID: DesignFacetID { descriptor.facetID }

  public init(
    descriptor: DesignSchemaDescriptor,
    entities: [DesignEntitySchema],
    indexes: Set<DesignIndexKind>
  ) throws(DesignDatabaseError) {
    var kinds = Set<DesignEntityKindID>()
    for entity in entities {
      guard kinds.insert(entity.kindID).inserted else {
        throw DesignDatabaseError.invalidToken(
          kind: "Duplicate entity kind in facet \(descriptor.facetID.rawValue)",
          value: entity.kindID.rawValue
        )
      }
    }
    self.descriptor = descriptor
    self.entities = entities.sorted { $0.kindID.rawValue < $1.kindID.rawValue }
    self.indexes = indexes.union([.entity, .facet, .change])
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      descriptor: container.decode(DesignSchemaDescriptor.self, forKey: .descriptor),
      entities: container.decode([DesignEntitySchema].self, forKey: .entities),
      indexes: container.decode(Set<DesignIndexKind>.self, forKey: .indexes)
    )
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case descriptor
    case entities
    case indexes
  }
#endif
}
