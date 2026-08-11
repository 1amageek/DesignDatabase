import CircuiteFoundation

public struct DesignDisjointMergeRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let baseRevision: DesignRevisionReference
  public let leftRevision: DesignRevisionReference
  public let rightRevision: DesignRevisionReference
  public let budget: DesignDisjointMergeBudget

  public init(
    baseRevision: DesignRevisionReference,
    leftRevision: DesignRevisionReference,
    rightRevision: DesignRevisionReference,
    budget: DesignDisjointMergeBudget
  ) throws(DesignDatabaseError) {
    guard leftRevision.databaseID == baseRevision.databaseID else {
      throw .crossDatabaseReference(
        expected: baseRevision.databaseID,
        actual: leftRevision.databaseID
      )
    }
    guard rightRevision.databaseID == baseRevision.databaseID else {
      throw .crossDatabaseReference(
        expected: baseRevision.databaseID,
        actual: rightRevision.databaseID
      )
    }
    guard leftRevision != rightRevision else {
      throw .invalidMergeRequest(
        reason: "The left and right merge revisions must be distinct."
      )
    }
    self.baseRevision = baseRevision
    self.leftRevision = leftRevision
    self.rightRevision = rightRevision
    self.budget = budget
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        baseRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .baseRevision
        ),
        leftRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .leftRevision
        ),
        rightRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .rightRevision
        ),
        budget: container.decode(
          DesignDisjointMergeBudget.self,
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
