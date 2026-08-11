public enum DesignCommitStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case committed(DesignCommitReceipt)
  case rejected(DesignCommitRejection)
  case inProgress
  case notRecorded
  case outcomeUnknown(DesignCommitUnknown)
}
