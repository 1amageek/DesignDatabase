import CircuiteFoundation

public struct DesignRevisionDiffRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let fromRevision: DesignRevisionReference
  public let toRevision: DesignRevisionReference
  public let budget: DesignRevisionDiffBudget

  public init(
    fromRevision: DesignRevisionReference,
    toRevision: DesignRevisionReference,
    budget: DesignRevisionDiffBudget
  ) throws(DesignDatabaseError) {
    guard fromRevision.databaseID == toRevision.databaseID else {
      throw .crossDatabaseReference(
        expected: fromRevision.databaseID,
        actual: toRevision.databaseID
      )
    }
    self.fromRevision = fromRevision
    self.toRevision = toRevision
    self.budget = budget
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        fromRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .fromRevision
        ),
        toRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .toRevision
        ),
        budget: container.decode(
          DesignRevisionDiffBudget.self,
          forKey: .budget
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
}
