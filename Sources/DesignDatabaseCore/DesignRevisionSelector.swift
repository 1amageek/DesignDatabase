import CircuiteFoundation

public enum DesignRevisionSelector: Sendable, Hashable, Codable {
  case exact(DesignRevisionReference)
  case named(DesignReferenceName)
}
