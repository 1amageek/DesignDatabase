import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeSnapshotLease: Sendable, Hashable {
  package let identifier: UInt64
  package let revision: DesignRevisionReference
}
