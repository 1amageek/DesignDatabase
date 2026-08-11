import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionChildReference: Sendable, Hashable {
  package let nodeDigest: ContentDigest
  package let minimumKey: DesignCanonicalKey
  package let maximumKey: DesignCanonicalKey
  package let subtreeEntryCount: UInt64
  package let subtreeNodeCount: UInt64
  package let level: UInt16
}
