import CircuiteFoundation

public struct DesignDisjointMergePublicationUnknown:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
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
