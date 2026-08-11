import CircuiteFoundation

public struct DesignMutationIdentityAssignments:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public let entities: [DesignEntityIdentityAssignment]
  public let relationOccurrences: [
    DesignRelationOccurrenceIdentityAssignment
  ]

  public init() {
    entities = []
    relationOccurrences = []
  }

  public init(
    entities: [DesignEntityIdentityAssignment],
    relationOccurrences: [DesignRelationOccurrenceIdentityAssignment]
  ) throws(DesignDatabaseError) {
    let orderedEntities = entities.sorted()
    let orderedOccurrences = relationOccurrences.sorted()
    guard Set(orderedEntities.map { $0.provisionalID }).count
      == orderedEntities.count else {
      throw .invalidMutationPlan(
        reason: "Identity assignments contain a duplicate provisional entity identity."
      )
    }
    guard Set(orderedOccurrences.map { $0.provisionalID }).count
      == orderedOccurrences.count else {
      throw .invalidMutationPlan(
        reason: "Identity assignments contain a duplicate provisional relation-occurrence identity."
      )
    }
    guard Set(orderedEntities.map { $0.permanentID }).count
      == orderedEntities.count else {
      throw .invalidMutationPlan(
        reason: "Identity assignments reuse a permanent entity identity."
      )
    }
    guard Set(orderedOccurrences.map { $0.permanentID }).count
      == orderedOccurrences.count else {
      throw .invalidMutationPlan(
        reason: "Identity assignments reuse a permanent relation-occurrence identity."
      )
    }
    self.entities = orderedEntities
    self.relationOccurrences = orderedOccurrences
  }

  public func entityID(
    for provisionalID: DesignProvisionalEntityID
  ) -> DesignEntityID? {
    entities.first(where: { $0.provisionalID == provisionalID })?.permanentID
  }

  public func relationOccurrenceID(
    for provisionalID: DesignProvisionalRelationOccurrenceID
  ) -> DesignRelationOccurrenceID? {
    relationOccurrences.first(where: {
      $0.provisionalID == provisionalID
    })?.permanentID
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        entities: container.decode(
          [DesignEntityIdentityAssignment].self,
          forKey: .entities
        ),
        relationOccurrences: container.decode(
          [DesignRelationOccurrenceIdentityAssignment].self,
          forKey: .relationOccurrences
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

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case entities
    case relationOccurrences
  }
#endif
}
