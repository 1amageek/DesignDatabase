import CircuiteFoundation

public enum DesignDependencyTarget: Sendable, Hashable, DesignDatabaseSerializable {
  case databaseRevision(DesignRevisionReference)
  case artifactContent(ArtifactID)
}
