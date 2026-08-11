import CircuiteFoundation

public struct DesignReferenceUpdateRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let operationID: DesignDatabaseOperationID
  public let name: DesignReferenceName
  public let expectedGeneration: UInt64
  public let expectedRevision: DesignRevisionReference?
  public let desiredRevision: DesignRevisionReference?
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    name: DesignReferenceName,
    expectedGeneration: UInt64,
    expectedRevision: DesignRevisionReference?,
    desiredRevision: DesignRevisionReference?,
    requestDigest: ContentDigest
  ) {
    self.operationID = operationID
    self.name = name
    self.expectedGeneration = expectedGeneration
    self.expectedRevision = expectedRevision
    self.desiredRevision = desiredRevision
    self.requestDigest = requestDigest
  }
}
