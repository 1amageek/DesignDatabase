public enum DesignDatabaseTermination: Sendable, Hashable, DesignDatabaseSerializable {
  case closed
  case alreadyClosed
  case cleanupFailed(reason: String)
}
