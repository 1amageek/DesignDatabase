import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionPhysicalNode: Sendable, Hashable {
  package let digest: ContentDigest
  package let family: DesignProjectionFamily
  package let codecVersion: DesignProjectionPhysicalCodecVersion
  package let physicalProfileDigest: ContentDigest
  package let kind: DesignProjectionNodeKind
  package let level: UInt16
  package let minimumKey: DesignCanonicalKey?
  package let maximumKey: DesignCanonicalKey?
  package let subtreeEntryCount: UInt64
  package let subtreeNodeCount: UInt64
  package let entries: [DesignProjectionEntry]
  package let children: [DesignProjectionChildReference]
  package let payload: [UInt8]

  package var itemCount: Int {
    switch kind {
    case .leaf: entries.count
    case .internal: children.count
    }
  }

  package var childReference: DesignProjectionChildReference? {
    guard let minimumKey, let maximumKey else { return nil }
    return DesignProjectionChildReference(
      nodeDigest: digest,
      minimumKey: minimumKey,
      maximumKey: maximumKey,
      subtreeEntryCount: subtreeEntryCount,
      subtreeNodeCount: subtreeNodeCount,
      level: level
    )
  }
}
