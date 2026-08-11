import CircuiteFoundation
import Database
import DesignDatabaseCore

public struct DesignDatabaseRuntimeRegistrationBundle: Sendable {
  public let schema: Schema
  public let runtimeConfiguration: DatabaseRuntimeConfiguration
  public let contributionIDs: [DesignDatabaseRuntimeContributionID]
  public let schemaFingerprint: ContentDigest
  public let designSchemaBundle: DesignSchemaBundle
  public var designSchemaBundleDigest: ContentDigest {
    designSchemaBundle.rootDigest
  }
  public let registrationDigest: ContentDigest
  public let mutationAdapters: [DesignSchemaID: any DesignDatabaseRuntimeMutationAdapter]
  public let physicalWriteReclaimers: [
    String: any DesignDatabaseRuntimePhysicalWriteReclaimer
  ]

  package init(
    schema: Schema,
    runtimeConfiguration: DatabaseRuntimeConfiguration,
    contributionIDs: [DesignDatabaseRuntimeContributionID],
    schemaFingerprint: ContentDigest,
    designSchemaBundle: DesignSchemaBundle,
    registrationDigest: ContentDigest,
    mutationAdapters: [DesignSchemaID: any DesignDatabaseRuntimeMutationAdapter],
    physicalWriteReclaimers: [
      String: any DesignDatabaseRuntimePhysicalWriteReclaimer
    ]
  ) {
    self.schema = schema
    self.runtimeConfiguration = runtimeConfiguration
    self.contributionIDs = contributionIDs
    self.schemaFingerprint = schemaFingerprint
    self.designSchemaBundle = designSchemaBundle
    self.registrationDigest = registrationDigest
    self.mutationAdapters = mutationAdapters
    self.physicalWriteReclaimers = physicalWriteReclaimers
  }
}
