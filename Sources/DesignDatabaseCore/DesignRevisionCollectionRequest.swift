import CircuiteFoundation

/// An immutable exact target set; operating budgets do not change its identity.
public struct DesignRevisionCollectionRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let revisions: [DesignRevisionReference]
  public let requestDigest: ContentDigest

  public init(operation: DesignDatabaseOperationReference,
              revisions: [DesignRevisionReference], requestDigest: ContentDigest) throws(DesignDatabaseError) {
    guard !revisions.isEmpty, revisions.allSatisfy({ $0.databaseID == operation.databaseID }),
          Set(revisions).count == revisions.count, requestDigest.algorithm == .sha256 else {
      throw .invalidMutationPlan(reason: "Collection requires unique exact revisions in one database and a SHA-256 digest.")
    }
    self.operation = operation
    self.revisions = revisions.sorted { $0.revisionID.description < $1.revisionID.description }
    self.requestDigest = requestDigest
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: CodingKey { case operation, revisions, requestDigest }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(operation: values.decode(DesignDatabaseOperationReference.self, forKey: .operation),
                  revisions: values.decode([DesignRevisionReference].self, forKey: .revisions),
                  requestDigest: values.decode(ContentDigest.self, forKey: .requestDigest))
  }
#endif
}
