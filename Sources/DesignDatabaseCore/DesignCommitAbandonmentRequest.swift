import CircuiteFoundation

public struct DesignCommitAbandonmentRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let operationID: DesignDatabaseOperationID
  public let targetOperation: DesignDatabaseOperationReference
  public let targetRequestDigest: ContentDigest
  public let reason: DesignCommitAbandonmentReason
  public let evidenceDigest: ContentDigest
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    reason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    requestDigest: ContentDigest
  ) {
    self.operationID = operationID
    self.targetOperation = targetOperation
    self.targetRequestDigest = targetRequestDigest
    self.reason = reason
    self.evidenceDigest = evidenceDigest
    self.requestDigest = requestDigest
  }
}
