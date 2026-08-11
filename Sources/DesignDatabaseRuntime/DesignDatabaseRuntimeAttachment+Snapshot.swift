import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func snapshotDescriptor(
    at revision: DesignRevisionReference,
    expectedDatabaseID: DesignDatabaseID
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeSnapshotDescriptor {
    guard revision.databaseID == expectedDatabaseID else {
      throw .databaseIdentityMismatch(
        expected: expectedDatabaseID.description,
        actual: revision.databaseID.description
      )
    }
    let databaseContext = try context()
    let expectedSchemaDigest = designSchemaBundleDigest
    let resolvedSchemaBundle = designSchemaBundle
    do {
      return try await databaseContext.withTransaction { transaction in
        let lifecycle = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: revision.revisionID.description,
          consistency: .serializable
        )
        try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
          lifecycle,
          revision: revision,
          using: SHA256ContentDigester()
        )
        guard let model = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: revision.revisionID.description,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.revisionNotFound(
            revision.revisionID.description
          )
        }
        return try await Self.snapshotDescriptor(
          from: model,
          revision: revision,
          expectedDatabaseID: expectedDatabaseID,
          expectedSchemaDigest: expectedSchemaDigest,
          designSchemaBundle: resolvedSchemaBundle,
          transaction: transaction,
          digester: SHA256ContentDigester()
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  package static func snapshotDescriptor(
    from model: DesignRevisionManifestModel,
    revision: DesignRevisionReference,
    expectedDatabaseID: DesignDatabaseID,
    expectedSchemaDigest: ContentDigest,
    designSchemaBundle: DesignSchemaBundle,
    transaction: DatabaseTransaction,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeSnapshotDescriptor {
    guard model.id == revision.revisionID.description,
          model.databaseID == expectedDatabaseID.description else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A revision manifest does not match its exact database identity."
      )
    }
    guard let parentCount = Int(exactly: model.parentCount), parentCount >= 0 else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A revision manifest contains an invalid parent count."
      )
    }
    let parentRevisionIDs = model.parentRevisionIDs.isEmpty
      ? []
      : model.parentRevisionIDs.split(
          separator: "\n",
          omittingEmptySubsequences: false
        ).map(String.init)
    guard parentRevisionIDs.count == parentCount,
          Set(parentRevisionIDs).count == parentRevisionIDs.count else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A revision manifest parent directory is not canonical."
      )
    }
    let parents: [DesignRevisionReference]
    do {
      parents = try parentRevisionIDs.map {
        DesignRevisionReference(
          databaseID: expectedDatabaseID,
          revisionID: try DesignRevisionID(hexadecimalValue: $0)
        )
      }
    } catch {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A revision manifest contains a malformed parent identity."
      )
    }
    let schemaDigest = try Self.snapshotDigest(
      algorithm: model.schemaRootDigestAlgorithm,
      value: model.schemaRootDigestValue,
      field: "schema root"
    )
    guard schemaDigest == expectedSchemaDigest else {
      throw DesignDatabaseRuntimeError.runtimeRegistrationMismatch(
        expected: expectedSchemaDigest.hexadecimalValue,
        actual: schemaDigest.hexadecimalValue
      )
    }
    guard designSchemaBundle.rootDigest == schemaDigest else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The runtime schema bundle does not match the revision schema root."
      )
    }
    let physicalDirectoryModel: DesignRevisionPhysicalIdentityDirectoryModel?
    do {
      physicalDirectoryModel = try await transaction.fetch(
        DesignRevisionPhysicalIdentityDirectoryModel.self,
        identifiedBy: revision.revisionID.description,
        consistency: .serializable
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard let physicalDirectoryModel else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A visible revision has no owned physical identity directory."
      )
    }
    _ = try DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
      model: physicalDirectoryModel,
      revision: revision,
      using: digester
    )
    let projectionState = try await DesignDatabaseRuntimeProjectionDirectory.load(
      revision: revision,
      databaseID: expectedDatabaseID,
      count: model.projectionDescriptorCount,
      encoded: model.projectionDescriptorDigests,
      transaction: transaction,
      digester: digester
    )
    let dependencyRootDigest = try Self.snapshotDigest(
      algorithm: model.dependencyRootDigestAlgorithm,
      value: model.dependencyRootDigestValue,
      field: "dependency root"
    )
    let directDependencyLock = try DesignDatabaseRuntimeDependencyLockDirectory
      .decode(
        count: model.dependencyLockEntryCount,
        encoded: model.dependencyLockEntries,
        expectedRootDigest: dependencyRootDigest,
        using: digester
      )
    return DesignDatabaseRuntimeSnapshotDescriptor(
      revision: revision,
      parents: parents,
      stateDigest: try Self.snapshotDigest(
        algorithm: model.stateDigestAlgorithm,
        value: model.stateDigestValue,
        field: "state"
      ),
      designSchemaBundle: designSchemaBundle,
      designSchemaBundleDigest: schemaDigest,
      directDependencyLock: directDependencyLock,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: try Self.snapshotDigest(
        algorithm: model.dependencyGraphDigestAlgorithm,
        value: model.dependencyGraphDigestValue,
        field: "semantic dependency graph"
      ),
      facetRoots: try DesignDatabaseRuntimeFacetRootDirectory.decode(
        count: model.facetRootCount,
        encoded: model.facetRoots
      ),
      directChangeRootDigest: try Self.snapshotDigest(
        algorithm: model.directChangeRootDigestAlgorithm,
        value: model.directChangeRootDigestValue,
        field: "direct change root"
      ),
      projectionSemantics: projectionState.descriptors,
      projectionDescriptorDigests: projectionState.descriptorDigests,
      materializationBindings: projectionState.bindings
    )
  }

  package static func snapshotDigest(
    algorithm: String,
    value: String,
    field: String
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      let digest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: algorithm),
        hexadecimalValue: value
      )
      guard digest.algorithm == .sha256 else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A revision manifest \(field) digest does not use SHA-256."
        )
      }
      return digest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A revision manifest contains a malformed \(field) digest."
      )
    }
  }
}
