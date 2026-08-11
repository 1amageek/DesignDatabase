public enum DesignReferenceUpdateResult: Sendable, Hashable, DesignDatabaseSerializable {
  case applied(DesignReferenceUpdateReceipt)
  case rejected(DesignReferenceUpdateRejection)
  case outcomeUnknown(DesignReferenceUpdateUnknown)
}
