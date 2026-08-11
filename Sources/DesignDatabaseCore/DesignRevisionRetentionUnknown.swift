import CircuiteFoundation

public struct DesignRevisionRetentionUnknown: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
  }
}
