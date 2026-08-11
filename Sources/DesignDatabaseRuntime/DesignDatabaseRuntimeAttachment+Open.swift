import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  public func inspectDatabase(
    expectedDatabaseID: DesignDatabaseID,
    requiredFeatureCapabilities: DesignCapabilitySet
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeCatalogDescriptor {
    let databaseContext = try context()
    let expectedSchemaFingerprint = schemaFingerprint
    let expectedDesignSchemaBundle = designSchemaBundle
    let expectedDesignSchemaBundleDigest = expectedDesignSchemaBundle.rootDigest
    let expectedRegistrationDigest = registrationDigest
    let expectedContributionCount = contributionIDs.count
    do {
      return try await databaseContext.withTransaction { transaction in
        guard let catalog = try await transaction.fetch(
          DesignDatabaseCatalogModel.self,
          identifiedBy: "catalog",
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.databaseNotFound
        }
        guard catalog.formatVersion == 1 else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The catalog format version is unsupported."
          )
        }
        guard catalog.databaseID == expectedDatabaseID.description else {
          throw DesignDatabaseRuntimeError.databaseIdentityMismatch(
            expected: expectedDatabaseID.description,
            actual: catalog.databaseID
          )
        }
        guard catalog.schemaFingerprintAlgorithm == expectedSchemaFingerprint.algorithm.rawValue,
              catalog.schemaFingerprintValue == expectedSchemaFingerprint.hexadecimalValue else {
          throw DesignDatabaseRuntimeError.runtimeRegistrationMismatch(
            expected: expectedSchemaFingerprint.hexadecimalValue,
            actual: catalog.schemaFingerprintValue
          )
        }
        guard catalog.registrationDigestAlgorithm == expectedRegistrationDigest.algorithm.rawValue,
              catalog.registrationDigestValue == expectedRegistrationDigest.hexadecimalValue else {
          throw DesignDatabaseRuntimeError.runtimeRegistrationMismatch(
            expected: expectedRegistrationDigest.hexadecimalValue,
            actual: catalog.registrationDigestValue
          )
        }
        guard catalog.designSchemaBundleDigestAlgorithm == expectedDesignSchemaBundleDigest.algorithm.rawValue,
              catalog.designSchemaBundleDigestValue == expectedDesignSchemaBundleDigest.hexadecimalValue else {
          throw DesignDatabaseRuntimeError.runtimeRegistrationMismatch(
            expected: expectedDesignSchemaBundleDigest.hexadecimalValue,
            actual: catalog.designSchemaBundleDigestValue
          )
        }

        let persistedSchemaBundle = try await Self.readSchemaBundle(
          expected: expectedDesignSchemaBundle,
          transaction: transaction
        )

        guard let persistedRegistration = try await transaction.fetch(
          DesignRuntimeRegistrationModel.self,
          identifiedBy: "active",
          consistency: .serializable
        ), persistedRegistration.schemaFingerprintAlgorithm == expectedSchemaFingerprint.algorithm.rawValue,
           persistedRegistration.schemaFingerprintValue == expectedSchemaFingerprint.hexadecimalValue,
           persistedRegistration.registrationDigestAlgorithm == expectedRegistrationDigest.algorithm.rawValue,
           persistedRegistration.registrationDigestValue == expectedRegistrationDigest.hexadecimalValue,
           persistedRegistration.contributionCount == Int64(expectedContributionCount) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The active runtime registration record is missing or inconsistent."
          )
        }

        let capabilityIDs = catalog.capabilityIDs.isEmpty
          ? []
          : catalog.capabilityIDs.split(
              separator: "\n",
              omittingEmptySubsequences: false
            ).map(String.init)
        guard capabilityIDs == capabilityIDs.sorted(),
              Set(capabilityIDs).count == capabilityIDs.count,
              catalog.capabilityCount == Int64(capabilityIDs.count) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The catalog capability directory is not canonical."
          )
        }
        let capabilityModelIDs = capabilityIDs.map {
          expectedDatabaseID.description + ":" + $0
        }
        let capabilityModels = try await transaction.fetch(
          DesignDatabaseCapabilityModel.self,
          identifiedBy: capabilityModelIDs,
          consistency: .serializable
        )
        guard capabilityModels.count == capabilityIDs.count else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "One or more declared capability records are missing."
          )
        }
        let featureCapabilities = try Self.featureCapabilities(
          models: capabilityModels,
          expectedDatabaseID: expectedDatabaseID
        )
        try Self.validateRequiredCapabilities(
          requiredFeatureCapabilities,
          offered: featureCapabilities
        )

        guard let main = try await transaction.fetch(
          DesignNamedReferenceModel.self,
          identifiedBy: "main",
          consistency: .serializable
        ), main.databaseID == expectedDatabaseID.description,
           main.generation > 0 else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The main reference is missing or invalid."
          )
        }
        guard let genesis = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: catalog.genesisRevisionID,
          consistency: .serializable
        ), genesis.databaseID == expectedDatabaseID.description,
           genesis.parentCount == 0 else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The genesis revision is missing or invalid."
          )
        }
        guard genesis.schemaRootDigestAlgorithm == expectedDesignSchemaBundleDigest.algorithm.rawValue,
              genesis.schemaRootDigestValue == expectedDesignSchemaBundleDigest.hexadecimalValue else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The genesis schema root does not match the active registration."
          )
        }
        guard let reachability = try await transaction.fetch(
          DesignReachabilityStateModel.self,
          identifiedBy: "active",
          consistency: .serializable
        ), reachability.databaseID == expectedDatabaseID.description,
           reachability.generation >= 0 else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The reachability generation state is missing or invalid."
          )
        }
        guard let identityAllocator = try await transaction.fetch(
          DesignIdentityAllocatorStateModel.self,
          identifiedBy: "active",
          consistency: .serializable
        ), identityAllocator.databaseID == expectedDatabaseID.description else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The database identity allocator is missing or invalid."
          )
        }

        let genesisRevisionID: DesignRevisionID
        let mainRevisionID: DesignRevisionID
        do {
          genesisRevisionID = try DesignRevisionID(
            hexadecimalValue: catalog.genesisRevisionID
          )
          mainRevisionID = try DesignRevisionID(
            hexadecimalValue: main.revisionID
          )
        } catch {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A persisted revision identity is malformed."
          )
        }
        guard let mainGeneration = UInt64(exactly: main.generation) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The main reference generation is outside UInt64 range."
          )
        }
        let genesisRevision = DesignRevisionReference(
          databaseID: expectedDatabaseID,
          revisionID: genesisRevisionID
        )
        let mainRevision = DesignRevisionReference(
          databaseID: expectedDatabaseID,
          revisionID: mainRevisionID
        )
        let genesisLifecycle = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: genesisRevisionID.description,
          consistency: .serializable
        )
        try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
          genesisLifecycle,
          revision: genesisRevision,
          using: SHA256ContentDigester()
        )
        _ = try await Self.snapshotDescriptor(
          from: genesis,
          revision: genesisRevision,
          expectedDatabaseID: expectedDatabaseID,
          expectedSchemaDigest: expectedDesignSchemaBundleDigest,
          designSchemaBundle: expectedDesignSchemaBundle,
          transaction: transaction,
          digester: SHA256ContentDigester()
        )
        guard let mainManifest = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: mainRevisionID.description,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The main reference targets a missing revision manifest."
          )
        }
        let mainLifecycle = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: mainRevisionID.description,
          consistency: .serializable
        )
        try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
          mainLifecycle,
          revision: mainRevision,
          using: SHA256ContentDigester()
        )
        _ = try await Self.snapshotDescriptor(
          from: mainManifest,
          revision: mainRevision,
          expectedDatabaseID: expectedDatabaseID,
          expectedSchemaDigest: expectedDesignSchemaBundleDigest,
          designSchemaBundle: expectedDesignSchemaBundle,
          transaction: transaction,
          digester: SHA256ContentDigester()
        )
        return DesignDatabaseRuntimeCatalogDescriptor(
          databaseID: expectedDatabaseID,
          genesisRevision: genesisRevision,
          mainRevision: mainRevision,
          mainGeneration: mainGeneration,
          featureCapabilities: featureCapabilities,
          schemaBundle: persistedSchemaBundle,
          schemaFingerprint: expectedSchemaFingerprint,
          registrationDigest: expectedRegistrationDigest
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .creationTransactionFailed(reason: String(describing: error))
    }
  }

  private static func readSchemaBundle(
    expected: DesignSchemaBundle,
    transaction: DatabaseTransaction
  ) async throws -> DesignSchemaBundle {
    let bundleID = expected.rootDigest.algorithm.rawValue
      + ":" + expected.rootDigest.hexadecimalValue
    guard let bundle = try await transaction.fetch(
      DesignSchemaBundleModel.self,
      identifiedBy: bundleID,
      consistency: .serializable
    ), bundle.id == bundleID,
       bundle.rootDigestAlgorithm == expected.rootDigest.algorithm.rawValue,
       bundle.rootDigestValue == expected.rootDigest.hexadecimalValue else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The exact schema bundle record is missing or inconsistent."
      )
    }
    let schemaIDs = bundle.memberIDs.isEmpty
      ? []
      : bundle.memberIDs.split(
          separator: "\n",
          omittingEmptySubsequences: false
        ).map(String.init)
    guard schemaIDs == schemaIDs.sorted(),
          Set(schemaIDs).count == schemaIDs.count,
          bundle.memberCount == Int64(schemaIDs.count) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The schema bundle member directory is not canonical."
      )
    }
    let modelIDs = schemaIDs.map { bundleID + ":" + $0 }
    let models = try await transaction.fetch(
      DesignSchemaBundleMemberModel.self,
      identifiedBy: modelIDs,
      consistency: .serializable
    )
    guard models.count == modelIDs.count else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "One or more exact schema bundle members are missing."
      )
    }
    var modelsBySchemaID: [String: DesignSchemaBundleMemberModel] = [:]
    for model in models {
      guard modelsBySchemaID.updateValue(model, forKey: model.schemaID) == nil else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The schema bundle contains a duplicate schema identifier."
        )
      }
    }
    let members: [DesignSchemaBundleMember] = try schemaIDs.map { schemaID in
      guard let model = modelsBySchemaID[schemaID],
            model.id == bundleID + ":" + schemaID,
            model.bundleID == bundleID,
            let major = UInt16(exactly: model.versionMajor),
            let minor = UInt16(exactly: model.versionMinor),
            let patch = UInt16(exactly: model.versionPatch) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "An exact schema bundle member is malformed."
        )
      }
      do {
        return DesignSchemaBundleMember(
          schemaID: try DesignSchemaID(rawValue: schemaID),
          version: SchemaVersion(major: major, minor: minor, patch: patch),
          canonicalDigest: try ContentDigest(
            algorithm: ContentDigestAlgorithm(
              rawValue: model.canonicalDigestAlgorithm
            ),
            hexadecimalValue: model.canonicalDigestValue
          )
        )
      } catch {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "An exact schema bundle member identity is malformed."
        )
      }
    }
    let reconstructed: DesignSchemaBundle
    do {
      reconstructed = try DesignSchemaBundle(
        members: members,
        rootDigest: expected.rootDigest
      )
    } catch {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The exact schema bundle violates its canonical contract."
      )
    }
    guard reconstructed == expected else {
      throw DesignDatabaseRuntimeError.runtimeRegistrationMismatch(
        expected: expected.rootDigest.hexadecimalValue,
        actual: bundle.rootDigestValue
      )
    }
    return reconstructed
  }

  private static func featureCapabilities(
    models: [DesignDatabaseCapabilityModel],
    expectedDatabaseID: DesignDatabaseID
  ) throws(DesignDatabaseRuntimeError) -> DesignCapabilitySet {
    do {
      let descriptors = try models.map { model in
        guard model.databaseID == expectedDatabaseID.description,
              model.id == expectedDatabaseID.description + ":" + model.capabilityID,
              let lowerMajor = UInt16(exactly: model.lowerMajor),
              let lowerMinor = UInt16(exactly: model.lowerMinor),
              let lowerPatch = UInt16(exactly: model.lowerPatch),
              let upperMajor = UInt16(exactly: model.upperMajor),
              let upperMinor = UInt16(exactly: model.upperMinor),
              let upperPatch = UInt16(exactly: model.upperPatch) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A persisted capability record is malformed."
          )
        }
        return DesignCapabilityDescriptor(
          capabilityID: try DesignCapabilityID(rawValue: model.capabilityID),
          versions: try SchemaVersionRange(
            lowerBound: SchemaVersion(
              major: lowerMajor,
              minor: lowerMinor,
              patch: lowerPatch
            ),
            upperBound: SchemaVersion(
              major: upperMajor,
              minor: upperMinor,
              patch: upperPatch
            )
          )
        )
      }
      return try DesignCapabilitySet(descriptors)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A persisted capability record violates the capability contract."
      )
    }
  }

  private static func validateRequiredCapabilities(
    _ required: DesignCapabilitySet,
    offered: DesignCapabilitySet
  ) throws(DesignDatabaseRuntimeError) {
    let offeredByID = Dictionary(
      uniqueKeysWithValues: offered.descriptors.map { ($0.capabilityID, $0) }
    )
    for requirement in required.descriptors {
      guard let descriptor = offeredByID[requirement.capabilityID] else {
        throw .missingFeatureCapability(requirement.capabilityID.rawValue)
      }
      guard descriptor.versions.intersection(with: requirement.versions) != nil else {
        throw .incompatibleFeatureCapability(requirement.capabilityID.rawValue)
      }
    }
  }
}
