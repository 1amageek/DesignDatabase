public enum DesignRevisionRetentionStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case applied(DesignRevisionRetentionReceipt)
  case rejected(DesignRevisionRetentionRejection)
  case inProgress
  case notRecorded
  case outcomeUnknown(DesignRevisionRetentionUnknown)
}
