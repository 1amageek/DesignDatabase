public struct DesignUniqueConstraint: Sendable, Hashable, DesignDatabaseSerializable {
  public let id: DesignUniqueConstraintID
  public let fields: [DesignFieldID]

  public init(
    id: DesignUniqueConstraintID,
    fields: [DesignFieldID]
  ) throws(DesignDatabaseError) {
    guard !fields.isEmpty else {
      throw .invalidToken(kind: "Unique constraint field set", value: id.rawValue)
    }
    guard Set(fields).count == fields.count else {
      throw .invalidToken(kind: "Duplicate unique constraint field", value: id.rawValue)
    }
    self.id = id
    self.fields = fields
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(DesignUniqueConstraintID.self, forKey: .id),
      fields: container.decode([DesignFieldID].self, forKey: .fields)
    )
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case id
    case fields
  }
#endif
}
