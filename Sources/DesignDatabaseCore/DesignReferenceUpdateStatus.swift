public enum DesignReferenceUpdateStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case applied(DesignReferenceUpdateReceipt)
  case rejected(DesignReferenceUpdateRejection)
  case notRecorded
  case outcomeUnknown(DesignReferenceUpdateUnknown)
}
