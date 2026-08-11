import CircuiteFoundation

public struct DesignRevisionRetentionRejection: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Reason: Sendable, Hashable, DesignDatabaseSerializable {
    case operationRequestConflict
    case claimUnavailable
    case claimAlreadyActive
    case claimPermanentlyReleased
    case revisionNotFound
    case revisionMismatch
    case generationMismatch(actual: UInt64)
  }

  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let reason: Reason
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    reason: Reason,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.reason = reason
    self.outcomeDigest = outcomeDigest
  }
}
