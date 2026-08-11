public enum DesignSpatialRelation: String, Sendable, Hashable, DesignDatabaseSerializable {
  case intersects
  case containedByQuery
  case containsQuery
}
