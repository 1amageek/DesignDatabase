import CircuiteFoundation

public struct DesignRevisionRetentionRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let operationID: DesignDatabaseOperationID
  public let claimID: DesignRevisionRetentionID
  public let revision: DesignRevisionReference
  public let reason: DesignRevisionRetentionReason
  public let evidenceDigest: ContentDigest
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    reason: DesignRevisionRetentionReason,
    evidenceDigest: ContentDigest,
    requestDigest: ContentDigest
  ) {
    self.operationID = operationID
    self.claimID = claimID
    self.revision = revision
    self.reason = reason
    self.evidenceDigest = evidenceDigest
    self.requestDigest = requestDigest
  }
}
