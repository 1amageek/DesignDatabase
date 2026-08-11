import CircuiteFoundation

public struct DesignReferenceUpdateReceipt: Sendable, Hashable, DesignDatabaseSerializable {
  public let operation: DesignDatabaseOperationReference
  public let name: DesignReferenceName
  public let previousRevision: DesignRevisionReference?
  public let currentRevision: DesignRevisionReference?
  public let generation: UInt64
  public let outcomeDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    name: DesignReferenceName,
    previousRevision: DesignRevisionReference?,
    currentRevision: DesignRevisionReference?,
    generation: UInt64,
    outcomeDigest: ContentDigest
  ) {
    self.operation = operation
    self.name = name
    self.previousRevision = previousRevision
    self.currentRevision = currentRevision
    self.generation = generation
    self.outcomeDigest = outcomeDigest
  }
}
