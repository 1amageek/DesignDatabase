import CircuiteFoundation

public struct DesignDisjointMergePublicationRejection:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public enum Reason: Sendable, Hashable, DesignDatabaseSerializable {
    case assessmentChanged
    case validatedStateMismatch
    case candidateRevisionCollision(DesignRevisionReference)
  }

  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest
  public let candidateDigest: ContentDigest
  public let reason: Reason
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    candidateDigest: ContentDigest,
    reason: Reason,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
    self.candidateDigest = candidateDigest
    self.reason = reason
    self.outcomeDigest = outcomeDigest
  }
}
