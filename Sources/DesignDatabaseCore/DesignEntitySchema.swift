import CircuiteFoundation

public struct DesignEntitySchema: Sendable, Hashable, DesignDatabaseSerializable {
  public let kindID: DesignEntityKindID
  public let fields: [DesignFieldSchema]
  public let relations: [DesignRelationSchema]
  public let uniqueConstraints: [DesignUniqueConstraint]

  public init(
    kindID: DesignEntityKindID,
    fields: [DesignFieldSchema],
    relations: [DesignRelationSchema],
    uniqueConstraints: [DesignUniqueConstraint] = []
  ) throws(DesignDatabaseError) {
    var fieldIDs = Set<DesignFieldID>()
    for field in fields {
      guard fieldIDs.insert(field.id).inserted else {
        throw DesignDatabaseError.invalidToken(
          kind: "Duplicate field identifier",
          value: field.id.rawValue
        )
      }
      guard !field.isNameIndexSource || field.valueKind == .string else {
        throw DesignDatabaseError.invalidToken(
          kind: "Name index field must use string values",
          value: field.id.rawValue
        )
      }
    }
    var relationIDs = Set<DesignRelationKindID>()
    for relation in relations {
      guard relationIDs.insert(relation.id).inserted else {
        throw DesignDatabaseError.invalidToken(
          kind: "Duplicate relation identifier",
          value: relation.id.rawValue
        )
      }
    }
    var constraintIDs = Set<DesignUniqueConstraintID>()
    for constraint in uniqueConstraints {
      guard constraintIDs.insert(constraint.id).inserted else {
        throw DesignDatabaseError.invalidToken(
          kind: "Duplicate unique constraint identifier",
          value: constraint.id.rawValue
        )
      }
      for field in constraint.fields where !fieldIDs.contains(field) {
        throw DesignDatabaseError.unknownField(field)
      }
    }
    self.kindID = kindID
    self.fields = fields.sorted { $0.id < $1.id }
    self.relations = relations.sorted { $0.id < $1.id }
    self.uniqueConstraints = uniqueConstraints.sorted { $0.id < $1.id }
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kindID: container.decode(DesignEntityKindID.self, forKey: .kindID),
      fields: container.decode([DesignFieldSchema].self, forKey: .fields),
      relations: container.decode([DesignRelationSchema].self, forKey: .relations),
      uniqueConstraints: container.decode([DesignUniqueConstraint].self, forKey: .uniqueConstraints)
    )
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case kindID
    case fields
    case relations
    case uniqueConstraints
  }
#endif
}
