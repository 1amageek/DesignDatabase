public enum DesignDatabaseRuntimeCreationStatus: Sendable, Hashable {
  case created(DesignDatabaseRuntimeCreationResult)
  case notRecorded
}
