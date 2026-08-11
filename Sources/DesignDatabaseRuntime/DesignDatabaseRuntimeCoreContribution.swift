import CircuiteFoundation
import Database
import DatabaseWire

package enum DesignDatabaseRuntimeCoreContribution {
  package static func make() throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeContribution {
    do {
      let entities = [
        try DesignDatabaseCatalogModel.schemaEntity,
        try DesignRevisionManifestModel.schemaEntity,
        try DesignRevisionLifecycleModel.schemaEntity,
        try DesignRevisionPhysicalIdentityDirectoryModel.schemaEntity,
        try DesignNamedReferenceModel.schemaEntity,
        try DesignCreationOperationModel.schemaEntity,
        try DesignDatabaseCapabilityModel.schemaEntity,
        try DesignRuntimeRegistrationModel.schemaEntity,
        try DesignSchemaBundleModel.schemaEntity,
        try DesignSchemaBundleMemberModel.schemaEntity,
        try DesignReferenceOperationModel.schemaEntity,
        try DesignReachabilityStateModel.schemaEntity,
        try DesignRevisionRetentionModel.schemaEntity,
        try DesignRetentionOperationModel.schemaEntity,
        try DesignOperationClaimModel.schemaEntity,
        try DesignCommitOperationModel.schemaEntity,
        try DesignDisjointMergeOperationModel.schemaEntity,
        try DesignCommitAbandonmentOperationModel.schemaEntity,
        try DesignCommitSubmissionModel.schemaEntity,
        try DesignCommitBuildIntentModel.schemaEntity,
        try DesignStagingRootModel.schemaEntity,
        try DesignStagingPhysicalIdentityDirectoryModel.schemaEntity,
        try DesignCollectionIntentModel.schemaEntity,
        try DesignCollectionPhysicalIdentityDirectoryModel.schemaEntity,
        try DesignPhysicalCollectionClaimModel.schemaEntity,
        try DesignValidatedMutationDirectoryModel.schemaEntity,
        try DesignPreparedMutationDirectoryModel.schemaEntity,
        try DesignIdentityAllocatorStateModel.schemaEntity,
        try DesignIdentityReservationModel.schemaEntity,
        try DesignProjectionSemanticDescriptorModel.schemaEntity,
        try DesignProjectionBindingModel.schemaEntity,
        try DesignProjectionMaterializationModel.schemaEntity,
        try DesignProjectionNodeModel.schemaEntity,
      ]
      let runtimes = [
        try DatabaseFrameworkRuntime.entity(DesignDatabaseCatalogModel.self),
        try DatabaseFrameworkRuntime.entity(DesignRevisionManifestModel.self),
        try DatabaseFrameworkRuntime.entity(DesignRevisionLifecycleModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignRevisionPhysicalIdentityDirectoryModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignNamedReferenceModel.self),
        try DatabaseFrameworkRuntime.entity(DesignCreationOperationModel.self),
        try DatabaseFrameworkRuntime.entity(DesignDatabaseCapabilityModel.self),
        try DatabaseFrameworkRuntime.entity(DesignRuntimeRegistrationModel.self),
        try DatabaseFrameworkRuntime.entity(DesignSchemaBundleModel.self),
        try DatabaseFrameworkRuntime.entity(DesignSchemaBundleMemberModel.self),
        try DatabaseFrameworkRuntime.entity(DesignReferenceOperationModel.self),
        try DatabaseFrameworkRuntime.entity(DesignReachabilityStateModel.self),
        try DatabaseFrameworkRuntime.entity(DesignRevisionRetentionModel.self),
        try DatabaseFrameworkRuntime.entity(DesignRetentionOperationModel.self),
        try DatabaseFrameworkRuntime.entity(DesignOperationClaimModel.self),
        try DatabaseFrameworkRuntime.entity(DesignCommitOperationModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignDisjointMergeOperationModel.self
        ),
        try DatabaseFrameworkRuntime.entity(
          DesignCommitAbandonmentOperationModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignCommitSubmissionModel.self),
        try DatabaseFrameworkRuntime.entity(DesignCommitBuildIntentModel.self),
        try DatabaseFrameworkRuntime.entity(DesignStagingRootModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignStagingPhysicalIdentityDirectoryModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignCollectionIntentModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignCollectionPhysicalIdentityDirectoryModel.self
        ),
        try DatabaseFrameworkRuntime.entity(
          DesignPhysicalCollectionClaimModel.self
        ),
        try DatabaseFrameworkRuntime.entity(
          DesignValidatedMutationDirectoryModel.self
        ),
        try DatabaseFrameworkRuntime.entity(
          DesignPreparedMutationDirectoryModel.self
        ),
        try DatabaseFrameworkRuntime.entity(
          DesignIdentityAllocatorStateModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignIdentityReservationModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignProjectionSemanticDescriptorModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignProjectionBindingModel.self),
        try DatabaseFrameworkRuntime.entity(
          DesignProjectionMaterializationModel.self
        ),
        try DatabaseFrameworkRuntime.entity(DesignProjectionNodeModel.self),
      ]
      let schema = try Schema(
        entities: entities,
        version: Schema.Version(1, 0, 0)
      )
      let fingerprint = try SchemaManifest(schema: schema).fingerprint()
      return try DesignDatabaseRuntimeContribution(
        coreID: DesignDatabaseRuntimeContributionID("lsi.design-database-runtime"),
        bindingDigest: ContentDigest(
          algorithm: .sha256,
          hexadecimalValue: hexadecimal(fingerprint.bytes)
        ),
        entities: entities,
        entityRuntimes: runtimes
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .frameworkConfigurationFailed(reason: String(describing: error))
    }
  }

  private static func hexadecimal<Bytes: Collection>(_ bytes: Bytes) -> String
  where Bytes.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var encoded: [UInt8] = []
    encoded.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      encoded.append(digits[Int(byte >> 4)])
      encoded.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: encoded, as: UTF8.self)
  }
}
