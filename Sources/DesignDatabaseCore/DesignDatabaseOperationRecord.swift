import CircuiteFoundation

public struct DesignDatabaseOperationRecord: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Outcome: Sendable, Hashable, DesignDatabaseSerializable {
    case retentionApplied(DesignRevisionRetentionReceipt)
    case retentionRejected(DesignRevisionRetentionRejection)
  }

  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let outcome: Outcome

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    outcome: Outcome
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.outcome = outcome
  }

  public var retentionSubmission: DesignRevisionRetentionSubmission {
    switch outcome {
    case .retentionApplied(let receipt):
      return .applied(receipt)
    case .retentionRejected(let rejection):
      return .rejected(rejection)
    }
  }

  public var retentionStatus: DesignRevisionRetentionStatus {
    switch outcome {
    case .retentionApplied(let receipt):
      return .applied(receipt)
    case .retentionRejected(let rejection):
      return .rejected(rejection)
    }
  }
}
