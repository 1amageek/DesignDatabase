import DesignDatabaseCore

package actor DesignDatabaseRuntimeSnapshotRegistry {
  private enum State {
    case open
    case closing
    case closed
  }

  private var state: State = .open
  private var snapshots: [UInt64: DesignDatabaseRuntimeSnapshot] = [:]

  package func register(
    _ snapshot: DesignDatabaseRuntimeSnapshot,
    identifiedBy identifier: UInt64
  ) throws(DesignDatabaseError) {
    guard state == .open else { throw .closed }
    guard snapshots[identifier] == nil else {
      throw .corruption("A runtime snapshot identifier was reused.")
    }
    snapshots[identifier] = snapshot
  }

  package func release(identifier: UInt64) {
    snapshots.removeValue(forKey: identifier)
  }

  package func closeAll() async {
    guard state == .open else { return }
    state = .closing
    let activeSnapshots = Array(snapshots.values)
    for snapshot in activeSnapshots {
      _ = await snapshot.close()
    }
    snapshots.removeAll(keepingCapacity: false)
    state = .closed
  }
}
