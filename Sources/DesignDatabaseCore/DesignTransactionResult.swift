import CircuiteFoundation

public struct DesignTransactionResult<Value: Sendable>: Sendable {
  public let value: Value
  public let baseRevision: DesignRevisionReference
  public let candidateRevision: DesignRevisionReference
  public let stateDigest: ContentDigest
  public let changes: DesignChangeSet
  public let diagnostics: [DesignDiagnostic]

  public init(
    value: Value,
    baseRevision: DesignRevisionReference,
    candidateRevision: DesignRevisionReference,
    stateDigest: ContentDigest,
    changes: DesignChangeSet,
    diagnostics: [DesignDiagnostic]
  ) {
    self.value = value
    self.baseRevision = baseRevision
    self.candidateRevision = candidateRevision
    self.stateDigest = stateDigest
    self.changes = changes
    self.diagnostics = diagnostics
  }
}
