import CircuiteFoundation

public struct DesignSchemaBundle: Sendable, Hashable, DesignDatabaseSerializable {
  public let members: [DesignSchemaBundleMember]
  public let rootDigest: ContentDigest

  public init(
    members: [DesignSchemaBundleMember],
    rootDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    let orderedMembers = members.sorted()
    var identifiers = Set<DesignSchemaID>()
    for member in orderedMembers {
      guard identifiers.insert(member.schemaID).inserted else {
        throw .invalidSchemaBundle(
          reason: "Schema identifier \(member.schemaID.rawValue) appears more than once."
        )
      }
    }
    self.members = orderedMembers
    self.rootDigest = rootDigest
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        members: container.decode([DesignSchemaBundleMember].self, forKey: .members),
        rootDigest: container.decode(ContentDigest.self, forKey: .rootDigest)
      )
    } catch let error as DesignDatabaseError {
      throw error
    }
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case members
    case rootDigest
  }
#endif
}
