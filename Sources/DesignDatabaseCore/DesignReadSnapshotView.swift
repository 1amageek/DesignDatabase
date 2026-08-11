import CircuiteFoundation

/// A non-owning projection of an exact snapshot owner.
///
/// The view deliberately has no close operation. Its query capability becomes
/// unusable after the owner closes the underlying snapshot.
public struct DesignReadSnapshotView: DesignReadSnapshotReading, Sendable {
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let designSchemaBundle: DesignSchemaBundle
  public let designSchemaBundleDigest: ContentDigest
  public let directDependencyLock: DesignDependencyLock
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let facetRoots: [DesignFacetRoot]
  public let directChangeRootDigest: ContentDigest
  public let projectionSemantics: [DesignProjectionSemanticDescriptor]
  public let materializationBindings: DesignProjectionMaterializationBindingSet

  private let queryOperation: @Sendable (DesignQueryRequest) async
    throws(DesignDatabaseError) -> DesignQueryPage

  public init(_ snapshot: any DesignReadSnapshot) {
    revision = snapshot.revision
    parents = snapshot.parents
    stateDigest = snapshot.stateDigest
    designSchemaBundle = snapshot.designSchemaBundle
    designSchemaBundleDigest = snapshot.designSchemaBundleDigest
    directDependencyLock = snapshot.directDependencyLock
    dependencyRootDigest = snapshot.dependencyRootDigest
    semanticDependencyGraphDigest = snapshot.semanticDependencyGraphDigest
    facetRoots = snapshot.facetRoots
    directChangeRootDigest = snapshot.directChangeRootDigest
    projectionSemantics = snapshot.projectionSemantics
    materializationBindings = snapshot.materializationBindings
    queryOperation = {
      (request: DesignQueryRequest) async throws(DesignDatabaseError)
        -> DesignQueryPage in
      try await snapshot.query(request)
    }
  }

  public func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    try await queryOperation(request)
  }
}
