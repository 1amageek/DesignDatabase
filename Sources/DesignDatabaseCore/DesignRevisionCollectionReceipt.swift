import CircuiteFoundation

public struct DesignRevisionCollectionReceipt: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let revisions: [DesignRevisionReference]
  public let originalRootSetDigest: ContentDigest
  public let physicalRootSetDigest: ContentDigest
  public let physicalIdentityDirectoryDigest: ContentDigest
  public let physicalIdentityCount: UInt64
  public let admittedReachabilityGeneration: UInt64
  public let completedReachabilityGeneration: UInt64
  public let intentStateDigest: ContentDigest

  public init(operation: DesignDatabaseOperationReference, requestDigest: ContentDigest,
              revisions: [DesignRevisionReference], originalRootSetDigest: ContentDigest,
              physicalRootSetDigest: ContentDigest, physicalIdentityDirectoryDigest: ContentDigest,
              physicalIdentityCount: UInt64, admittedReachabilityGeneration: UInt64,
              completedReachabilityGeneration: UInt64, intentStateDigest: ContentDigest) {
    self.operation = operation; self.requestDigest = requestDigest; self.revisions = revisions
    self.originalRootSetDigest = originalRootSetDigest; self.physicalRootSetDigest = physicalRootSetDigest
    self.physicalIdentityDirectoryDigest = physicalIdentityDirectoryDigest
    self.physicalIdentityCount = physicalIdentityCount
    self.admittedReachabilityGeneration = admittedReachabilityGeneration
    self.completedReachabilityGeneration = completedReachabilityGeneration; self.intentStateDigest = intentStateDigest
  }
}
