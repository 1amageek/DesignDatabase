import CircuiteFoundation

public struct DesignMutationPlan: Sendable, Hashable, DesignDatabaseSerializable {
  public static let currentSchemaVersion = 3

  public let schemaVersion: Int
  public let databaseID: DesignDatabaseID
  public let baseRevision: DesignRevisionReference
  public let designSchemaBundleDigest: ContentDigest
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let sourceEvidenceDigest: ContentDigest
  public let budget: DesignMutationPlanBudget
  public let segments: [DesignMutationPlanSegment]
  public let dependencyLockUpdate: DesignDependencyLockUpdate?
  public let planDigest: ContentDigest

  public init(
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    sourceEvidenceDigest: ContentDigest,
    budget: DesignMutationPlanBudget,
    segments: [DesignMutationPlanSegment],
    planDigest: ContentDigest,
    dependencyLockUpdate: DesignDependencyLockUpdate? = nil
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.databaseID = databaseID
    self.baseRevision = baseRevision
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.sourceEvidenceDigest = sourceEvidenceDigest
    self.budget = budget
    self.segments = segments
    self.dependencyLockUpdate = dependencyLockUpdate
    self.planDigest = planDigest
  }
}
