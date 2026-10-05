public enum DesignDatabaseRuntimeTermination: Sendable, Equatable {
  case closed
  case alreadyClosed
  case cleanupFailed(reason: String)
}
