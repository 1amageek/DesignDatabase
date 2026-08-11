public enum DesignProjectionFamily: String, Sendable, Hashable, DesignDatabaseSerializable, CaseIterable, Comparable {
  case entity
  case facet
  case name
  case hierarchy
  case connectivity
  case spatial
  case crossFacet = "cross-facet"
  case directChange = "direct-change"
  case dependency

  public static func < (
    lhs: DesignProjectionFamily,
    rhs: DesignProjectionFamily
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
