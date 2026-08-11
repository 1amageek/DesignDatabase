import CircuiteFoundation

public enum DesignMutation: Sendable, Hashable, DesignDatabaseSerializable {
  case create(facet: DesignFacetID, kind: DesignEntityKindID, requestedID: DesignEntityID?)
  case delete(DesignEntityKey)
  case setField(entity: DesignEntityKey, field: DesignFieldID, value: DesignValue?)
  case replaceRelation(
    entity: DesignEntityKey,
    relation: DesignRelationKindID,
    targets: Set<DesignEntityID>
  )
  case replaceSpatialEntries(entity: DesignEntityKey, entries: [DesignSpatialEntry])
}
