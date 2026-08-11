public enum DesignCommitResult: Sendable, Hashable, DesignDatabaseSerializable {
  case committed(DesignCommitReceipt)
  case rejected(DesignCommitRejection)
  case outcomeUnknown(DesignCommitUnknown)
}
