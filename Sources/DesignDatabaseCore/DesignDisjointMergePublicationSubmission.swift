import CircuiteFoundation

public struct DesignDisjointMergePublicationSubmission:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let operationID: DesignDatabaseOperationID
  public let candidate: DesignDisjointMergeCandidate
  public let validatedStateRevision: DesignRevisionReference
  public let validatedStateCommit: DesignCommitSubmission
  public let budget: DesignDisjointMergePublicationBudget
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    candidate: DesignDisjointMergeCandidate,
    validatedStateRevision: DesignRevisionReference,
    validatedStateCommit: DesignCommitSubmission,
    budget: DesignDisjointMergePublicationBudget,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    let databaseID = candidate.baseRevision.databaseID
    guard validatedStateRevision.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: validatedStateRevision.databaseID
      )
    }
    guard validatedStateCommit.plan.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: validatedStateCommit.plan.databaseID
      )
    }
    guard validatedStateCommit.plan.baseRevision.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: validatedStateCommit.plan.baseRevision.databaseID
      )
    }
    schemaVersion = Self.currentSchemaVersion
    self.operationID = operationID
    self.candidate = candidate
    self.validatedStateRevision = validatedStateRevision
    self.validatedStateCommit = validatedStateCommit
    self.budget = budget
    self.requestDigest = requestDigest
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "The disjoint-merge publication schema version is unsupported."
      )
    }
    do {
      try self.init(
        operationID: container.decode(
          DesignDatabaseOperationID.self,
          forKey: .operationID
        ),
        candidate: container.decode(
          DesignDisjointMergeCandidate.self,
          forKey: .candidate
        ),
        validatedStateRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .validatedStateRevision
        ),
        validatedStateCommit: container.decode(
          DesignCommitSubmission.self,
          forKey: .validatedStateCommit
        ),
        budget: container.decode(
          DesignDisjointMergePublicationBudget.self,
          forKey: .budget
        ),
        requestDigest: container.decode(
          ContentDigest.self,
          forKey: .requestDigest
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
