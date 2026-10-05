import CircuiteFoundation

public struct DesignRevisionCollectionProgress: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let deletedPhysicalIdentityCount: UInt64
  public let physicalIdentityCount: UInt64
  public let intentStateDigest: ContentDigest

  public init(operation: DesignDatabaseOperationReference, requestDigest: ContentDigest,
              deletedPhysicalIdentityCount: UInt64, physicalIdentityCount: UInt64,
              intentStateDigest: ContentDigest) {
    self.operation = operation; self.requestDigest = requestDigest
    self.deletedPhysicalIdentityCount = deletedPhysicalIdentityCount
    self.physicalIdentityCount = physicalIdentityCount; self.intentStateDigest = intentStateDigest
  }
}
