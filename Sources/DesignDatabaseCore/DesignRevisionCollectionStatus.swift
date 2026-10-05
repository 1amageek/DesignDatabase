import CircuiteFoundation

public enum DesignRevisionCollectionStatus: Sendable, Hashable, DesignDatabaseSerializable {
  case notRecorded
  case inProgress(DesignRevisionCollectionProgress)
  case collected(DesignRevisionCollectionReceipt)
  case outcomeUnknown(operation: DesignDatabaseOperationReference, requestDigest: ContentDigest)
}
