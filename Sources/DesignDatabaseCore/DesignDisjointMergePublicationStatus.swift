public enum DesignDisjointMergePublicationStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case notRecorded
  case published(DesignDisjointMergePublicationReceipt)
  case rejected(DesignDisjointMergePublicationRejection)
  case outcomeUnknown(DesignDisjointMergePublicationUnknown)
}
