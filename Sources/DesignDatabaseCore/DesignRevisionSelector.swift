import CircuiteFoundation

public enum DesignRevisionSelector: Sendable, Hashable, DesignDatabaseSerializable {
  case exact(DesignRevisionReference)
  case named(DesignReferenceName)
}
