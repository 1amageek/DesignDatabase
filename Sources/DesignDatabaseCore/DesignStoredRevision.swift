import CircuiteFoundation

public struct DesignStoredRevision: Sendable, Codable {
  public let manifest: DesignRevisionManifest
  public let entities: [DesignEntityID: DesignEntityRecord]
  public let changeSet: DesignChangeSet

  public init(
    manifest: DesignRevisionManifest,
    entities: [DesignEntityID: DesignEntityRecord],
    changeSet: DesignChangeSet
  ) {
    self.manifest = manifest
    self.entities = entities
    self.changeSet = changeSet
  }
}
