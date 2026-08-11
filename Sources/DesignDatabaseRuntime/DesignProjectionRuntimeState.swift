import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionRuntimeState: Sendable {
  package let descriptors: [DesignProjectionSemanticDescriptor]
  package let descriptorDigests: [DesignProjectionFamily: ContentDigest]
  package let bindings: DesignProjectionMaterializationBindingSet
  package let materializations: [
    DesignProjectionFamily: DesignProjectionRuntimeMaterialization
  ]
}
