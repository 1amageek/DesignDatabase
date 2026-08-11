import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimeCatalogDescriptor: Sendable, Hashable {
  public let databaseID: DesignDatabaseID
  public let genesisRevision: DesignRevisionReference
  public let mainRevision: DesignRevisionReference
  public let mainGeneration: UInt64
  public let featureCapabilities: DesignCapabilitySet
  public let schemaBundle: DesignSchemaBundle
  public let schemaFingerprint: ContentDigest
  public let registrationDigest: ContentDigest

  package init(
    databaseID: DesignDatabaseID,
    genesisRevision: DesignRevisionReference,
    mainRevision: DesignRevisionReference,
    mainGeneration: UInt64,
    featureCapabilities: DesignCapabilitySet,
    schemaBundle: DesignSchemaBundle,
    schemaFingerprint: ContentDigest,
    registrationDigest: ContentDigest
  ) {
    self.databaseID = databaseID
    self.genesisRevision = genesisRevision
    self.mainRevision = mainRevision
    self.mainGeneration = mainGeneration
    self.featureCapabilities = featureCapabilities
    self.schemaBundle = schemaBundle
    self.schemaFingerprint = schemaFingerprint
    self.registrationDigest = registrationDigest
  }
}
