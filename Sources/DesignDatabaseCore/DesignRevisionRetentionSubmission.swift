public enum DesignRevisionRetentionSubmission: Sendable, Hashable, DesignDatabaseSerializable {
  case applied(DesignRevisionRetentionReceipt)
  case rejected(DesignRevisionRetentionRejection)
  case outcomeUnknown(DesignRevisionRetentionUnknown)
}
