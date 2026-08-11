import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimeMutationValidation: Sendable {
  public let databaseID: DesignDatabaseID
  public let baseRevision: DesignRevisionReference
  public let candidateRevision: DesignRevisionReference
  public let designSchemaBundleDigest: ContentDigest
  public let directDependencyLock: DesignDependencyLock
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let baseFacetRoots: [DesignFacetRoot]
  public let budget: DesignMutationPlanBudget
  public let reads: DesignDatabaseRuntimeReadSnapshot
  private let projectionReader: DesignProjectionTreeReader

  package init(
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    candidateRevision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    directDependencyLock: DesignDependencyLock,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    baseFacetRoots: [DesignFacetRoot],
    budget: DesignMutationPlanBudget,
    reads: DesignDatabaseRuntimeReadSnapshot,
    projectionReader: DesignProjectionTreeReader
  ) {
    self.databaseID = databaseID
    self.baseRevision = baseRevision
    self.candidateRevision = candidateRevision
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.directDependencyLock = directDependencyLock
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.baseFacetRoots = baseFacetRoots
    self.budget = budget
    self.reads = reads
    self.projectionReader = projectionReader
  }

  /// Queries a bounded semantic projection from the exact immutable base
  /// revision used by this mutation validation.
  public func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    try await projectionReader.query(request)
  }
}
