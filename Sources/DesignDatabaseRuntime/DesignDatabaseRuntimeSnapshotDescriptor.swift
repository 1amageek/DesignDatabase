import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeSnapshotDescriptor: Sendable {
  package let revision: DesignRevisionReference
  package let parents: [DesignRevisionReference]
  package let stateDigest: ContentDigest
  package let designSchemaBundle: DesignSchemaBundle
  package let designSchemaBundleDigest: ContentDigest
  package let directDependencyLock: DesignDependencyLock
  package let dependencyRootDigest: ContentDigest
  package let semanticDependencyGraphDigest: ContentDigest
  package let facetRoots: [DesignFacetRoot]
  package let directChangeRootDigest: ContentDigest
  package let projectionSemantics: [DesignProjectionSemanticDescriptor]
  package let projectionDescriptorDigests: [DesignProjectionFamily: ContentDigest]
  package let materializationBindings: DesignProjectionMaterializationBindingSet
}
