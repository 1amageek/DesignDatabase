import CircuiteFoundation

public struct DesignRevisionRetentionClaim: Sendable, Hashable, DesignDatabaseSerializable {
  public let claimID: DesignRevisionRetentionID
  public let revision: DesignRevisionReference
  public let ownerSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let reason: DesignRevisionRetentionReason
  public let evidenceDigest: ContentDigest
  public let generation: UInt64
  public let state: DesignRevisionRetentionState

  public init(
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    ownerSubjectScopeID: DesignAuthorizationSubjectScopeID,
    reason: DesignRevisionRetentionReason,
    evidenceDigest: ContentDigest,
    generation: UInt64,
    state: DesignRevisionRetentionState
  ) {
    self.claimID = claimID
    self.revision = revision
    self.ownerSubjectScopeID = ownerSubjectScopeID
    self.reason = reason
    self.evidenceDigest = evidenceDigest
    self.generation = generation
    self.state = state
  }
}
