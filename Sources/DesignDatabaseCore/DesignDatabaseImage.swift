import CircuiteFoundation

public struct DesignDatabaseImage: Sendable, Codable {
  public let databaseID: DesignDatabaseID
  public let schemas: [DesignFacetSchema]
  public let capabilities: DesignCapabilitySet
  public let revisions: [DesignRevisionID: DesignStoredRevision]
  public let references: [DesignReferenceName: DesignRevisionReference]
  public let nextEntityValue: UInt64

  public init(
    databaseID: DesignDatabaseID,
    schemas: [DesignFacetSchema],
    capabilities: DesignCapabilitySet,
    revisions: [DesignRevisionID: DesignStoredRevision],
    references: [DesignReferenceName: DesignRevisionReference],
    nextEntityValue: UInt64
  ) {
    self.databaseID = databaseID
    self.schemas = schemas
    self.capabilities = capabilities
    self.revisions = revisions
    self.references = references
    self.nextEntityValue = nextEntityValue
  }
}
