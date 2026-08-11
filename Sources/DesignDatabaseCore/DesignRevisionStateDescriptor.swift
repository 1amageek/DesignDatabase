import CircuiteFoundation

public struct DesignRevisionStateDescriptor: Sendable, Hashable, DesignDatabaseSerializable {
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let designSchemaBundleDigest: ContentDigest
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let facetRoots: [DesignFacetRoot]
  public let directChangeRootDigest: ContentDigest

  public init(
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference],
    stateDigest: ContentDigest,
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    directChangeRootDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    guard parents.allSatisfy({ $0.databaseID == revision.databaseID }) else {
      throw .invalidRevisionDiff(
        reason: "Every revision parent must belong to the same database."
      )
    }
    self.revision = revision
    self.parents = parents
    self.stateDigest = stateDigest
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.facetRoots = try DesignFacetRoot.canonicalizing(facetRoots)
    self.directChangeRootDigest = directChangeRootDigest
  }
}
