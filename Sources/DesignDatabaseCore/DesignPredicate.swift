import CircuiteFoundation

public indirect enum DesignPredicate: Sendable, Hashable, DesignDatabaseSerializable {
  case fieldEquals(DesignFieldID, DesignValue)
  case hasRelation(DesignRelationKindID, target: DesignEntityID?)
  case and([DesignPredicate])
  case or([DesignPredicate])
  case not(DesignPredicate)
}
