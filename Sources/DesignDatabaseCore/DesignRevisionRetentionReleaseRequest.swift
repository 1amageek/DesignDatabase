import CircuiteFoundation

public struct DesignRevisionRetentionReleaseRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let operationID: DesignDatabaseOperationID
  public let claimID: DesignRevisionRetentionID
  public let expectedRevision: DesignRevisionReference
  public let expectedGeneration: UInt64
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    claimID: DesignRevisionRetentionID,
    expectedRevision: DesignRevisionReference,
    expectedGeneration: UInt64,
    requestDigest: ContentDigest
  ) {
    self.operationID = operationID
    self.claimID = claimID
    self.expectedRevision = expectedRevision
    self.expectedGeneration = expectedGeneration
    self.requestDigest = requestDigest
  }
}
