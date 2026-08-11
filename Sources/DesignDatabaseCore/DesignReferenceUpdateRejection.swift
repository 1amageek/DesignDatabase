import CircuiteFoundation

public struct DesignReferenceUpdateRejection: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Reason: Sendable, Hashable, DesignDatabaseSerializable {
    case preconditionMismatch(
      actualGeneration: UInt64,
      actualRevision: DesignRevisionReference?
    )
    case desiredRevisionNotFound(DesignRevisionReference)
  }

  public let operation: DesignDatabaseOperationReference
  public let name: DesignReferenceName
  public let requestDigest: ContentDigest
  public let reason: Reason
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    name: DesignReferenceName,
    requestDigest: ContentDigest,
    reason: Reason,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.name = name
    self.requestDigest = requestDigest
    self.reason = reason
    self.outcomeDigest = outcomeDigest
  }
}
