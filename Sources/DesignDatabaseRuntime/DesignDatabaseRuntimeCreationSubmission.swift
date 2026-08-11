public enum DesignDatabaseRuntimeCreationSubmission: Sendable, Hashable {
  case created(DesignDatabaseRuntimeCreationResult)
  case outcomeUnknown(DesignDatabaseRuntimeCreationUnknown)
}
