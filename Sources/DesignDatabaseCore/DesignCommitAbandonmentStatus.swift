public enum DesignCommitAbandonmentStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case abandoned(DesignCommitAbandonmentReceipt)
  case rejected(DesignCommitAbandonmentRejection)
  case notRecorded
  case outcomeUnknown(DesignCommitAbandonmentUnknown)
}
