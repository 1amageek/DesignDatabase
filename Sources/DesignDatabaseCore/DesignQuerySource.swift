import CircuiteFoundation

public enum DesignQuerySource: Sendable, Hashable, Codable {
  case entities(Set<DesignEntityID>)
  case facet(DesignFacetID, kind: DesignEntityKindID?)
  case name(
    facet: DesignFacetID,
    kind: DesignEntityKindID?,
    field: DesignFieldID,
    value: String
  )
  case hierarchyChildren(parent: DesignEntityID)
  case connected(start: Set<DesignEntityID>, relations: Set<DesignRelationKindID>)
  case crossFacet(start: Set<DesignEntityID>, relations: Set<DesignRelationKindID>)
  case dependents(of: Set<DesignEntityID>, relations: Set<DesignRelationKindID>)
  case spatial(
    container: DesignEntityID,
    layer: DesignIndexKey?,
    bounds: DesignIntegerBounds,
    relation: DesignSpatialRelation
  )
  case changed(since: DesignRevisionReference)
}
