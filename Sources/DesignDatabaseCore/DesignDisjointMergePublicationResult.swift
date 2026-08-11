public enum DesignDisjointMergePublicationResult: Sendable, Hashable, DesignDatabaseSerializable {
  case published(DesignDisjointMergePublicationReceipt)
  case rejected(DesignDisjointMergePublicationRejection)
  case outcomeUnknown(DesignDisjointMergePublicationUnknown)
}
