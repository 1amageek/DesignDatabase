import CircuiteFoundation

/// Provides non-owning read access to one exact immutable revision.
///
/// This contract exposes semantic identity and bounded query operations without
/// exposing lifetime termination. The owner remains responsible for closing the
/// underlying `DesignReadSnapshot`.
public protocol DesignReadSnapshotReading: Sendable {
  var revision: DesignRevisionReference { get }
  var parents: [DesignRevisionReference] { get }
  var stateDigest: ContentDigest { get }
  var designSchemaBundle: DesignSchemaBundle { get }
  var designSchemaBundleDigest: ContentDigest { get }
  var directDependencyLock: DesignDependencyLock { get }
  var dependencyRootDigest: ContentDigest { get }
  var semanticDependencyGraphDigest: ContentDigest { get }
  var facetRoots: [DesignFacetRoot] { get }
  var directChangeRootDigest: ContentDigest { get }
  var projectionSemantics: [DesignProjectionSemanticDescriptor] { get }
  var materializationBindings: DesignProjectionMaterializationBindingSet { get }

  func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage
}
