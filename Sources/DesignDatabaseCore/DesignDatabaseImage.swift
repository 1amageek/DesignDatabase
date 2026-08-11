import CircuiteFoundation

public struct DesignDatabaseImage: Sendable, Hashable, DesignDatabaseSerializable {
  public let databaseID: DesignDatabaseID
  public let schemas: [DesignFacetSchema]
  public let capabilities: DesignCapabilitySet
  public let revisions: [DesignRevisionID: DesignStoredRevision]
  public let references: [DesignReferenceName: DesignRevisionReference]
  public let retentionClaims: [DesignRevisionRetentionID: DesignRevisionRetentionClaim]
  public let operationRecords: [
    DesignDatabaseOperationReference: DesignDatabaseOperationRecord
  ]
  public let persistenceGeneration: UInt64
  public let reachabilityGeneration: UInt64
  public let nextEntityValue: UInt64

  public init(
    databaseID: DesignDatabaseID,
    schemas: [DesignFacetSchema],
    capabilities: DesignCapabilitySet,
    revisions: [DesignRevisionID: DesignStoredRevision],
    references: [DesignReferenceName: DesignRevisionReference],
    retentionClaims: [DesignRevisionRetentionID: DesignRevisionRetentionClaim] = [:],
    operationRecords: [
      DesignDatabaseOperationReference: DesignDatabaseOperationRecord
    ] = [:],
    persistenceGeneration: UInt64 = 1,
    reachabilityGeneration: UInt64 = 1,
    nextEntityValue: UInt64
  ) {
    self.databaseID = databaseID
    self.schemas = schemas
    self.capabilities = capabilities
    self.revisions = revisions
    self.references = references
    self.retentionClaims = retentionClaims
    self.operationRecords = operationRecords
    self.persistenceGeneration = persistenceGeneration
    self.reachabilityGeneration = reachabilityGeneration
    self.nextEntityValue = nextEntityValue
  }
}
