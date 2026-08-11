import CircuiteFoundation

public struct DesignReferenceRevisionManifest: Sendable, Hashable, DesignDatabaseSerializable {
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let schemaDigests: [DesignSchemaID: ContentDigest]
  public let changeSetDigest: ContentDigest
  public let provenance: ExecutionProvenance?
  public let createdAt: ExecutionTimestamp

  public init(
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference],
    stateDigest: ContentDigest,
    schemaDigests: [DesignSchemaID: ContentDigest],
    changeSetDigest: ContentDigest,
    provenance: ExecutionProvenance?,
    createdAt: ExecutionTimestamp
  ) {
    self.revision = revision
    self.parents = parents
    self.stateDigest = stateDigest
    self.schemaDigests = schemaDigests
    self.changeSetDigest = changeSetDigest
    self.provenance = provenance
    self.createdAt = createdAt
  }
}
