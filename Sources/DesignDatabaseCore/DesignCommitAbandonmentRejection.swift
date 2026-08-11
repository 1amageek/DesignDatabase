import CircuiteFoundation

public struct DesignCommitAbandonmentRejection: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Reason: Sendable, Hashable, DesignDatabaseSerializable {
    case targetNotRecorded
    case targetOperationKindMismatch
    case targetRequestMismatch(actual: ContentDigest)
    case targetAlreadyCommitted(outcomeDigest: ContentDigest)
    case targetAlreadyRejected(outcomeDigest: ContentDigest)
  }

  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let targetOperation: DesignDatabaseOperationReference
  public let targetRequestDigest: ContentDigest
  public let abandonmentReason: DesignCommitAbandonmentReason
  public let evidenceDigest: ContentDigest
  public let reason: Reason
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    abandonmentReason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    reason: Reason,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.targetOperation = targetOperation
    self.targetRequestDigest = targetRequestDigest
    self.abandonmentReason = abandonmentReason
    self.evidenceDigest = evidenceDigest
    self.reason = reason
    self.outcomeDigest = outcomeDigest
  }
}
