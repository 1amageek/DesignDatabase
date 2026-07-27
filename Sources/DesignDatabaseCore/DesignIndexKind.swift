public enum DesignIndexKind: String, Sendable, Hashable, Codable, CaseIterable {
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
