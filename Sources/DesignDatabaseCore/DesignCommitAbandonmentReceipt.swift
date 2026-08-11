import CircuiteFoundation

public struct DesignCommitAbandonmentReceipt: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let targetOperation: DesignDatabaseOperationReference
  public let targetRequestDigest: ContentDigest
  public let reason: DesignCommitAbandonmentReason
  public let evidenceDigest: ContentDigest
  public let targetCommitOutcomeDigest: ContentDigest
  public let stagingRootTerminalized: Bool
  public let reachabilityGeneration: UInt64
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    reason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    targetCommitOutcomeDigest: ContentDigest,
    stagingRootTerminalized: Bool,
    reachabilityGeneration: UInt64,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.targetOperation = targetOperation
    self.targetRequestDigest = targetRequestDigest
    self.reason = reason
    self.evidenceDigest = evidenceDigest
    self.targetCommitOutcomeDigest = targetCommitOutcomeDigest
    self.stagingRootTerminalized = stagingRootTerminalized
    self.reachabilityGeneration = reachabilityGeneration
    self.outcomeDigest = outcomeDigest
  }
}
