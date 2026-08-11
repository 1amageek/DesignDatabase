/// Owns one exact immutable revision lease.
///
/// Semantic page APIs are added independently as their materialization families
/// become available. Closing the snapshot releases its revision lifetime from the
/// owning database handle.
public protocol DesignReadSnapshot: DesignReadSnapshotReading {
  func close() async -> DesignSnapshotTermination
}
