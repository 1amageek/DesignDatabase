public enum DesignIndexKind: String, Sendable, Hashable, DesignDatabaseSerializable, CaseIterable {
  case entity
  case facet
  case name
  case hierarchy
  case connectivity
  case spatial
  case crossFacet
  case change
  case dependency
}
