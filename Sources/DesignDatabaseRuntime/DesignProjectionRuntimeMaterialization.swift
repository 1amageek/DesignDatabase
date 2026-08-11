import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionRuntimeMaterialization: Sendable {
  package let descriptor: DesignProjectionSemanticDescriptor
  package let descriptorDigest: ContentDigest
  package let semanticAccumulator: DesignProjectionSemanticAccumulator
  package let reference: DesignProjectionMaterializationReference
  package let rootLevel: UInt16
  package let totalNodeCount: UInt64

  package init(
    descriptor: DesignProjectionSemanticDescriptor,
    descriptorDigest: ContentDigest,
    semanticAccumulator: DesignProjectionSemanticAccumulator,
    reference: DesignProjectionMaterializationReference,
    rootLevel: UInt16,
    totalNodeCount: UInt64
  ) {
    self.descriptor = descriptor
    self.descriptorDigest = descriptorDigest
    self.semanticAccumulator = semanticAccumulator
    self.reference = reference
    self.rootLevel = rootLevel
    self.totalNodeCount = totalNodeCount
  }

  package func inheritedTree() -> DesignProjectionTreeMaterialization {
    DesignProjectionTreeMaterialization(
      descriptor: descriptor,
      descriptorDigest: descriptorDigest,
      semanticAccumulator: semanticAccumulator,
      reference: reference,
      rootLevel: rootLevel,
      totalNodeCount: totalNodeCount,
      nodes: []
    )
  }
}
