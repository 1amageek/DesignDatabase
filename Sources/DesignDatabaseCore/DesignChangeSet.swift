import CircuiteFoundation

public struct DesignChangeSet: Sendable, Hashable, DesignDatabaseSerializable {
  public let baseRevision: DesignRevisionReference
  public let targetRevision: DesignRevisionReference
  public let changes: [DesignEntityChange]
  public let digest: ContentDigest

  public init(
    baseRevision: DesignRevisionReference,
    targetRevision: DesignRevisionReference,
    changes: [DesignEntityChange],
    digest: ContentDigest
  ) {
    self.baseRevision = baseRevision
    self.targetRevision = targetRevision
    self.changes = changes
    self.digest = digest
  }
}
