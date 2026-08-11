import CircuiteFoundation

public struct DesignStoredRevision: Sendable, Hashable, DesignDatabaseSerializable {
  public let manifest: DesignReferenceRevisionManifest
  public let entities: [DesignEntityID: DesignEntityRecord]
  public let changeSet: DesignChangeSet

  public init(
    manifest: DesignReferenceRevisionManifest,
    entities: [DesignEntityID: DesignEntityRecord],
    changeSet: DesignChangeSet
  ) {
    self.manifest = manifest
    self.entities = entities
    self.changeSet = changeSet
  }
}
