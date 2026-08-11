import CircuiteFoundation

public struct DesignDisjointMergePublicationReceipt:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let candidateDigest: ContentDigest
  public let baseRevision: DesignRevisionReference
  public let parentRevisions: [DesignRevisionReference]
  public let validatedStateRevision: DesignRevisionReference
  public let validatedStateCommitOperation: DesignDatabaseOperationReference
  public let validatedStateCommitRequestDigest: ContentDigest
  public let validatedStatePlanDigest: ContentDigest
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
    candidateDigest: ContentDigest,
    baseRevision: DesignRevisionReference,
    parentRevisions: [DesignRevisionReference],
    validatedStateRevision: DesignRevisionReference,
    validatedStateCommitOperation: DesignDatabaseOperationReference,
    validatedStateCommitRequestDigest: ContentDigest,
    validatedStatePlanDigest: ContentDigest,
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
    self.candidateDigest = candidateDigest
    self.baseRevision = baseRevision
    self.parentRevisions = parentRevisions
    self.validatedStateRevision = validatedStateRevision
    self.validatedStateCommitOperation = validatedStateCommitOperation
    self.validatedStateCommitRequestDigest = validatedStateCommitRequestDigest
    self.validatedStatePlanDigest = validatedStatePlanDigest
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
