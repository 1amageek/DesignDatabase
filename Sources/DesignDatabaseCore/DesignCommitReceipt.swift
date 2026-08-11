import CircuiteFoundation

public struct DesignCommitReceipt: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let planDigest: ContentDigest
  public let baseRevision: DesignRevisionReference
  public let candidateRevision: DesignRevisionReference
  public let stateDigest: ContentDigest
  public let changeSetDigest: ContentDigest
  public let designSchemaBundleDigest: ContentDigest
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let facetRoots: [DesignFacetRoot]
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    baseRevision: DesignRevisionReference,
    candidateRevision: DesignRevisionReference,
    stateDigest: ContentDigest,
    changeSetDigest: ContentDigest,
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.planDigest = planDigest
    self.baseRevision = baseRevision
    self.candidateRevision = candidateRevision
    self.stateDigest = stateDigest
    self.changeSetDigest = changeSetDigest
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.facetRoots = facetRoots
    self.outcomeDigest = outcomeDigest
  }
}
