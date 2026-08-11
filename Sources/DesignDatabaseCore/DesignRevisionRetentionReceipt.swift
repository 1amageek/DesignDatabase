import CircuiteFoundation

public struct DesignRevisionRetentionReceipt: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let claimID: DesignRevisionRetentionID
  public let revision: DesignRevisionReference
  public let generation: UInt64
  public let reachabilityGeneration: UInt64
  public let state: DesignRevisionRetentionState
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    generation: UInt64,
    reachabilityGeneration: UInt64,
    state: DesignRevisionRetentionState,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.claimID = claimID
    self.revision = revision
    self.generation = generation
    self.reachabilityGeneration = reachabilityGeneration
    self.state = state
    self.outcomeDigest = outcomeDigest
  }
}
