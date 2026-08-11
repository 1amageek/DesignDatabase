import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore

public struct DesignDatabaseRuntimeGenesisRequest: Sendable {
  public let locator: DesignDatabaseLocator
  public let databaseID: DesignDatabaseID
  public let genesisRevisionID: DesignRevisionID
  public let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let operationID: DesignDatabaseOperationID
  public let declaredFeatureCapabilities: DesignCapabilitySet
  public let initialSchemaBundle: DesignSchemaBundle
  public let designSchemaBundleDigest: ContentDigest
  public let registrationDigest: ContentDigest
  public let requestDigest: ContentDigest

  public init(
    locator: DesignDatabaseLocator,
    databaseID: DesignDatabaseID,
    genesisRevisionID: DesignRevisionID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    operationID: DesignDatabaseOperationID,
    declaredFeatureCapabilities: DesignCapabilitySet,
    initialSchemaBundle: DesignSchemaBundle,
    registrationDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) throws(DesignDatabaseRuntimeError) {
    self.locator = locator
    self.databaseID = databaseID
    self.genesisRevisionID = genesisRevisionID
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.operationID = operationID
    self.declaredFeatureCapabilities = declaredFeatureCapabilities
    self.initialSchemaBundle = initialSchemaBundle
    self.designSchemaBundleDigest = initialSchemaBundle.rootDigest
    self.registrationDigest = registrationDigest

    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.RuntimeGenesisRequest"
    )
    encoder.append(locator.namespace)
    encoder.append(UInt32(locator.segments.count))
    for segment in locator.segments {
      encoder.append(segment)
    }
    encoder.append(databaseID.description)
    encoder.append(genesisRevisionID.description)
    encoder.append(operationID.rawValue)
    encoder.append(UInt32(declaredFeatureCapabilities.descriptors.count))
    for descriptor in declaredFeatureCapabilities.descriptors {
      encoder.append(descriptor.capabilityID.rawValue)
      encoder.append(descriptor.versions.lowerBound.major)
      encoder.append(descriptor.versions.lowerBound.minor)
      encoder.append(descriptor.versions.lowerBound.patch)
      encoder.append(descriptor.versions.upperBound.major)
      encoder.append(descriptor.versions.upperBound.minor)
      encoder.append(descriptor.versions.upperBound.patch)
    }
    encoder.append(initialSchemaBundle.rootDigest)
    encoder.append(UInt32(initialSchemaBundle.members.count))
    for member in initialSchemaBundle.members {
      encoder.append(member.schemaID.rawValue)
      encoder.append(member.version.major)
      encoder.append(member.version.minor)
      encoder.append(member.version.patch)
      encoder.append(member.canonicalDigest)
    }
    requestDigest = try encoder.finalize(using: digester)
  }
}
