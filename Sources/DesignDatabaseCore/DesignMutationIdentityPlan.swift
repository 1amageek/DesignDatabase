public struct DesignMutationIdentityPlan: Sendable, Hashable, DesignDatabaseSerializable {
  public let provisionalEntityIDs: [DesignProvisionalEntityID]
  public let provisionalRelationOccurrenceIDs: [
    DesignProvisionalRelationOccurrenceID
  ]

  public init() {
    provisionalEntityIDs = []
    provisionalRelationOccurrenceIDs = []
  }

  public init(
    provisionalEntityIDs: [DesignProvisionalEntityID],
    provisionalRelationOccurrenceIDs: [
      DesignProvisionalRelationOccurrenceID
    ]
  ) throws(DesignDatabaseError) {
    let orderedEntities = provisionalEntityIDs.sorted()
    let orderedOccurrences = provisionalRelationOccurrenceIDs.sorted()
    guard Set(orderedEntities).count == orderedEntities.count else {
      throw .invalidMutationPlan(
        reason: "A segment contains a duplicate provisional entity identity."
      )
    }
    guard Set(orderedOccurrences).count == orderedOccurrences.count else {
      throw .invalidMutationPlan(
        reason: "A segment contains a duplicate provisional relation-occurrence identity."
      )
    }
    self.provisionalEntityIDs = orderedEntities
    self.provisionalRelationOccurrenceIDs = orderedOccurrences
  }

  public var isEmpty: Bool {
    provisionalEntityIDs.isEmpty
      && provisionalRelationOccurrenceIDs.isEmpty
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        provisionalEntityIDs: container.decode(
          [DesignProvisionalEntityID].self,
          forKey: .provisionalEntityIDs
        ),
        provisionalRelationOccurrenceIDs: container.decode(
          [DesignProvisionalRelationOccurrenceID].self,
          forKey: .provisionalRelationOccurrenceIDs
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
    case provisionalEntityIDs
    case provisionalRelationOccurrenceIDs
  }
#endif
}
