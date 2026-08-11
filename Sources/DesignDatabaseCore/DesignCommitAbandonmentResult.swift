public enum DesignCommitAbandonmentResult: Sendable, Hashable, DesignDatabaseSerializable {
  case abandoned(DesignCommitAbandonmentReceipt)
  case rejected(DesignCommitAbandonmentRejection)
  case outcomeUnknown(DesignCommitAbandonmentUnknown)
}
