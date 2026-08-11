import CircuiteFoundation

public enum DesignEntityChange: Sendable, Hashable, DesignDatabaseSerializable {
  case created(DesignEntityID)
  case deleted(DesignEntityID)
  case fieldChanged(entity: DesignEntityID, field: DesignFieldID)
  case relationChanged(entity: DesignEntityID, relation: DesignRelationKindID)
  case spatialChanged(DesignEntityID)
}
