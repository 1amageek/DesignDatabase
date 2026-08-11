public enum DesignDatabaseRuntimeReadError: Error, Sendable, Hashable {
  case invalidReadCount(Int)
  case budgetExceeded(limit: UInt64, requested: UInt64)
  case snapshotClosed
}
