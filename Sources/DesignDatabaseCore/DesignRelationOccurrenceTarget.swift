import CircuiteFoundation

public enum DesignRelationOccurrenceTarget: Sendable, Hashable, DesignDatabaseSerializable {
  case local(DesignEntityID)
  case exact(DesignEntityReference)
}
