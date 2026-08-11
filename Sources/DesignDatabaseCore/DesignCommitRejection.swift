import CircuiteFoundation

public struct DesignCommitRejection: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Reason: Sendable, Hashable, DesignDatabaseSerializable {
    case baseRevisionNotFound(DesignRevisionReference)
    case schemaBundleMismatch(expected: ContentDigest, actual: ContentDigest)
    case dependencyRootMismatch(expected: ContentDigest, actual: ContentDigest)
    case dependencyGraphMismatch(expected: ContentDigest, actual: ContentDigest)
    case adapterUnavailable(schemaID: DesignSchemaID, adapterVersion: String)
    case invalidSegmentPayload(
      segmentID: DesignMutationPlanSegmentID,
      reason: String
    )
    case validationFailed(
      diagnostics: [DesignDiagnostic],
      diagnosticsDigest: ContentDigest
    )
    case budgetExceeded(limit: UInt64, requested: UInt64)
    case candidateRevisionCollision(DesignRevisionReference)
    case abandonedByMaintenance(
      operation: DesignDatabaseOperationReference,
      requestDigest: ContentDigest,
      reason: DesignCommitAbandonmentReason,
      evidenceDigest: ContentDigest
    )
  }

  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let planDigest: ContentDigest
  public let reason: Reason
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    reason: Reason,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.planDigest = planDigest
    self.reason = reason
    self.outcomeDigest = outcomeDigest
  }
}
