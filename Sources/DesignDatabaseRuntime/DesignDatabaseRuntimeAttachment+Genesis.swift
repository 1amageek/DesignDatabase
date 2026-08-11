import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  public func createGenesis(
    _ request: DesignDatabaseRuntimeGenesisRequest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeCreationSubmission {
    try validateGenesisBinding(request)
    let operation = DesignDatabaseOperationReference(
      databaseID: request.databaseID,
      authorizationSubjectScopeID: request.authorizationSubjectScopeID,
      operationID: request.operationID
    )
    let operationKey = Self.operationKey(operation)
    let directDependencyLock: DesignDependencyLock
    let dependencyRoot: ContentDigest
    do {
      directDependencyLock = try DesignDependencyLock(entries: [])
      dependencyRoot = try DesignDependencyLockDigest.root(
        directDependencyLock,
        using: digester
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "The canonical empty dependency lock could not be constructed."
      )
    }
    let dependencyGraph: ContentDigest
    do {
      dependencyGraph = try DesignSemanticDependencyGraphDigest.root(
        DesignSemanticDependencyGraphIdentity(nodes: [], edges: []),
        using: digester
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "The canonical empty semantic dependency graph could not be constructed."
      )
    }
    let facetProjection = try DesignProjectionTreeBuilder().build(
      family: .facet,
      entries: [],
      digester: digester
    )
    let genesisRevision = DesignRevisionReference(
      databaseID: request.databaseID,
      revisionID: request.genesisRevisionID
    )
    let facetProjectionModels = try facetProjection.models(
      databaseID: request.databaseID,
      revision: genesisRevision
    )
    let revisionPhysicalIdentityDirectory = try
      DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
        revision: genesisRevision,
        projection: facetProjectionModels,
        using: digester
      ).model()
    let stateDigest = try DesignDatabaseRuntimeFacetRootDirectory.stateDigest(
      designSchemaBundleDigest: request.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRoot,
      semanticDependencyGraphDigest: dependencyGraph,
      facetRoots: [],
      projectionSemantics: [facetProjection.descriptor],
      using: digester
    )
    let directChangeRoot = try Self.digest(
      domain: "DesignDatabase.RuntimeEmptyDirectChangeRoot",
      values: [request.databaseID.description],
      using: digester
    )
    let outcomeDigest = try Self.creationOutcomeDigest(
      request: request,
      operation: operation,
      using: digester
    )
    let models = try Self.makeGenesisModels(
      request: request,
      operation: operation,
      schemaFingerprint: schemaFingerprint,
      designSchemaBundleDigest: designSchemaBundleDigest,
      stateDigest: stateDigest,
      directDependencyLock: directDependencyLock,
      dependencyRoot: dependencyRoot,
      dependencyGraph: dependencyGraph,
      directChangeRoot: directChangeRoot,
      projection: facetProjectionModels,
      revisionPhysicalIdentityDirectory: revisionPhysicalIdentityDirectory,
      projectionDirectory: try DesignDatabaseRuntimeProjectionDirectory.encode([
        facetProjection,
      ]),
      outcomeDigest: outcomeDigest,
      contributionCount: contributionIDs.count,
      digester: digester
    )
    let databaseContext = try context()

    do {
      let result = try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let existingClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        let existing = try await transaction.fetch(
          DesignCreationOperationModel.self,
          identifiedBy: models.operation.id,
          consistency: .serializable
        )
        if let existingClaim, let existing {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            existingClaim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.creationKind,
            requestDigest: request.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.creationIdempotencyConflict(
              operation: operationKey
            )
          }
          return try await Self.replayedCreationResult(
            existing: existing,
            request: request,
            operation: operation,
            transaction: transaction,
            expectedOutcomeDigest: outcomeDigest
          )
        }
        guard existingClaim == nil, existing == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A creation operation claim and outcome are not atomic."
          )
        }

        if let existingCatalog = try await transaction.fetch(
          DesignDatabaseCatalogModel.self,
          identifiedBy: models.catalog.id,
          consistency: .serializable
        ) {
          throw DesignDatabaseRuntimeError.databaseAlreadyExists(
            existingDatabaseID: existingCatalog.databaseID
          )
        }

        try await transaction.save(models.catalog, precondition: .notExists)
        try await transaction.save(models.revision, precondition: .notExists)
        try await transaction.save(
          models.revisionLifecycle,
          precondition: .notExists
        )
        try await transaction.save(models.reference, precondition: .notExists)
        try await transaction.save(models.registration, precondition: .notExists)
        try await transaction.save(models.reachability, precondition: .notExists)
        try await transaction.save(models.identityAllocator, precondition: .notExists)
        for node in models.projection.nodes {
          try await transaction.save(node, precondition: .notExists)
        }
        try await transaction.save(
          models.projection.descriptor,
          precondition: .notExists
        )
        try await transaction.save(
          models.projection.materialization,
          precondition: .notExists
        )
        try await transaction.save(
          models.projection.binding,
          precondition: .notExists
        )
        try await transaction.save(
          models.revisionPhysicalIdentityDirectory,
          precondition: .notExists
        )
        try await transaction.save(models.schemaBundle, precondition: .notExists)
        for member in models.schemaBundleMembers {
          try await transaction.save(member, precondition: .notExists)
        }
        for capability in models.capabilities {
          try await transaction.save(capability, precondition: .notExists)
        }
        try await transaction.save(models.operationClaim, precondition: .notExists)
        try await transaction.save(models.operation, precondition: .notExists)

        return DesignDatabaseRuntimeCreationResult(
          operation: operation,
          genesisRevision: DesignRevisionReference(
            databaseID: request.databaseID,
            revisionID: request.genesisRevisionID
          ),
          registrationDigest: request.registrationDigest,
          outcomeDigest: outcomeDigest,
          wasReplayed: false
        )
      }
      return .created(result)
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignDatabaseRuntimeCreationUnknown(
          operation: operation,
          requestDigest: request.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .creationTransactionFailed(reason: String(describing: error))
    }
  }

  public func creationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeCreationStatus {
    let databaseContext = try context()
    let operationKey = Self.operationKey(operation)
    do {
      return try await databaseContext.withTransaction { transaction in
        let operationClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        let existing = try await transaction.fetch(
          DesignCreationOperationModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        guard operationClaim != nil || existing != nil else {
          return .notRecorded
        }
        guard let operationClaim, let existing else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A creation operation claim and outcome are not atomic."
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          operationClaim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.creationKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError.creationIdempotencyConflict(
            operation: operationKey
          )
        }
        guard existing.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
              existing.requestDigestValue == requestDigest.hexadecimalValue else {
          throw DesignDatabaseRuntimeError.creationIdempotencyConflict(
            operation: operationKey
          )
        }
        guard existing.databaseID == operation.databaseID.description,
              existing.subjectScopeID == operation.authorizationSubjectScopeID.description,
              existing.operationID == operation.operationID.rawValue else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The creation operation key does not match its persisted scope."
          )
        }
        let catalog = try await Self.requireCatalog(transaction: transaction)
        guard catalog.databaseID == operation.databaseID.description,
              catalog.genesisRevisionID == existing.genesisRevisionID else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The creation operation outcome does not match the catalog."
          )
        }
        let registrationDigest = try Self.contentDigest(
          algorithm: catalog.registrationDigestAlgorithm,
          value: catalog.registrationDigestValue
        )
        let designSchemaBundleDigest = try Self.contentDigest(
          algorithm: catalog.designSchemaBundleDigestAlgorithm,
          value: catalog.designSchemaBundleDigestValue
        )
        try await Self.requireSchemaBundle(
          self.designSchemaBundle,
          transaction: transaction
        )
        let outcomeDigest = try Self.contentDigest(
          algorithm: existing.outcomeDigestAlgorithm,
          value: existing.outcomeDigestValue
        )
        let expectedOutcomeDigest = try Self.creationOutcomeDigest(
          operation: operation,
          requestDigest: requestDigest,
          genesisRevisionID: existing.genesisRevisionID,
          designSchemaBundleDigest: designSchemaBundleDigest,
          registrationDigest: registrationDigest,
          using: digester
        )
        guard outcomeDigest == expectedOutcomeDigest else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "The creation outcome digest does not match its persisted payload."
          )
        }
        return .created(
          DesignDatabaseRuntimeCreationResult(
            operation: operation,
            genesisRevision: DesignRevisionReference(
              databaseID: operation.databaseID,
              revisionID: try DesignRevisionID(
                hexadecimalValue: existing.genesisRevisionID
              )
            ),
            registrationDigest: registrationDigest,
            outcomeDigest: outcomeDigest,
            wasReplayed: true
          )
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .creationTransactionFailed(reason: String(describing: error))
    }
  }

  private func validateGenesisBinding(
    _ request: DesignDatabaseRuntimeGenesisRequest
  ) throws(DesignDatabaseRuntimeError) {
    guard request.locator == locator else {
      throw .genesisRequestBindingMismatch(
        reason: "The request locator does not match the attached container."
      )
    }
    guard request.registrationDigest == registrationDigest else {
      throw .genesisRequestBindingMismatch(
        reason: "The request registration digest does not match the attached runtime."
      )
    }
    guard request.initialSchemaBundle == designSchemaBundle else {
      throw .genesisRequestBindingMismatch(
        reason: "The request schema bundle does not match the attached runtime contributions."
      )
    }
  }

  private static func replayedCreationResult(
    existing: DesignCreationOperationModel,
    request: DesignDatabaseRuntimeGenesisRequest,
    operation: DesignDatabaseOperationReference,
    transaction: DatabaseTransaction,
    expectedOutcomeDigest: ContentDigest
  ) async throws -> DesignDatabaseRuntimeCreationResult {
    let operationKey = operationKey(operation)
    guard existing.databaseID == request.databaseID.description,
          existing.subjectScopeID == request.authorizationSubjectScopeID.description,
          existing.operationID == request.operationID.rawValue,
          existing.requestDigestAlgorithm == request.requestDigest.algorithm.rawValue,
          existing.requestDigestValue == request.requestDigest.hexadecimalValue else {
      throw DesignDatabaseRuntimeError.creationIdempotencyConflict(
        operation: operationKey
      )
    }
    guard existing.genesisRevisionID == request.genesisRevisionID.description,
          existing.outcomeDigestAlgorithm == expectedOutcomeDigest.algorithm.rawValue,
          existing.outcomeDigestValue == expectedOutcomeDigest.hexadecimalValue else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The persisted creation outcome does not match its canonical request."
      )
    }
    let catalog = try await requireCatalog(transaction: transaction)
    guard catalog.databaseID == request.databaseID.description,
          catalog.genesisRevisionID == request.genesisRevisionID.description,
          catalog.designSchemaBundleDigestAlgorithm == request.designSchemaBundleDigest.algorithm.rawValue,
          catalog.designSchemaBundleDigestValue == request.designSchemaBundleDigest.hexadecimalValue,
          catalog.registrationDigestAlgorithm == request.registrationDigest.algorithm.rawValue,
          catalog.registrationDigestValue == request.registrationDigest.hexadecimalValue else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The persisted catalog does not match its creation receipt."
      )
    }
    try await requireSchemaBundle(
      request.initialSchemaBundle,
      transaction: transaction
    )
    guard let reference = try await transaction.fetch(
      DesignNamedReferenceModel.self,
      identifiedBy: "main",
      consistency: .serializable
    ), reference.databaseID == request.databaseID.description,
       reference.revisionID == request.genesisRevisionID.description,
       reference.generation == 1 else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The genesis main reference is missing or inconsistent."
      )
    }
    return DesignDatabaseRuntimeCreationResult(
      operation: operation,
      genesisRevision: DesignRevisionReference(
        databaseID: request.databaseID,
        revisionID: request.genesisRevisionID
      ),
      registrationDigest: request.registrationDigest,
      outcomeDigest: expectedOutcomeDigest,
      wasReplayed: true
    )
  }

  private static func requireCatalog(
    transaction: DatabaseTransaction
  ) async throws -> DesignDatabaseCatalogModel {
    guard let catalog = try await transaction.fetch(
      DesignDatabaseCatalogModel.self,
      identifiedBy: "catalog",
      consistency: .serializable
    ) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A creation receipt exists without a catalog."
      )
    }
    return catalog
  }

  private static func makeGenesisModels(
    request: DesignDatabaseRuntimeGenesisRequest,
    operation: DesignDatabaseOperationReference,
    schemaFingerprint: ContentDigest,
    designSchemaBundleDigest: ContentDigest,
    stateDigest: ContentDigest,
    directDependencyLock: DesignDependencyLock,
    dependencyRoot: ContentDigest,
    dependencyGraph: ContentDigest,
    directChangeRoot: ContentDigest,
    projection: DesignProjectionPersistedModels,
    revisionPhysicalIdentityDirectory:
      DesignRevisionPhysicalIdentityDirectoryModel,
    projectionDirectory: String,
    outcomeDigest: ContentDigest,
    contributionCount: Int,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> (
    catalog: DesignDatabaseCatalogModel,
    revision: DesignRevisionManifestModel,
    revisionLifecycle: DesignRevisionLifecycleModel,
    reference: DesignNamedReferenceModel,
    registration: DesignRuntimeRegistrationModel,
    reachability: DesignReachabilityStateModel,
    identityAllocator: DesignIdentityAllocatorStateModel,
    schemaBundle: DesignSchemaBundleModel,
    schemaBundleMembers: [DesignSchemaBundleMemberModel],
    capabilities: [DesignDatabaseCapabilityModel],
    projection: DesignProjectionPersistedModels,
    revisionPhysicalIdentityDirectory:
      DesignRevisionPhysicalIdentityDirectoryModel,
    operationClaim: DesignOperationClaimModel,
    operation: DesignCreationOperationModel
  ) {
    var catalog = DesignDatabaseCatalogModel()
    catalog.databaseID = request.databaseID.description
    catalog.genesisRevisionID = request.genesisRevisionID.description
    catalog.schemaFingerprintAlgorithm = schemaFingerprint.algorithm.rawValue
    catalog.schemaFingerprintValue = schemaFingerprint.hexadecimalValue
    catalog.designSchemaBundleDigestAlgorithm = designSchemaBundleDigest.algorithm.rawValue
    catalog.designSchemaBundleDigestValue = designSchemaBundleDigest.hexadecimalValue
    catalog.registrationDigestAlgorithm = request.registrationDigest.algorithm.rawValue
    catalog.registrationDigestValue = request.registrationDigest.hexadecimalValue
    catalog.creationRequestDigestAlgorithm = request.requestDigest.algorithm.rawValue
    catalog.creationRequestDigestValue = request.requestDigest.hexadecimalValue
    catalog.capabilityCount = Int64(
      request.declaredFeatureCapabilities.descriptors.count
    )
    catalog.capabilityIDs = request.declaredFeatureCapabilities.descriptors
      .map(\.capabilityID.rawValue)
      .joined(separator: "\n")

    var revision = DesignRevisionManifestModel()
    revision.id = request.genesisRevisionID.description
    revision.databaseID = request.databaseID.description
    revision.stateDigestAlgorithm = stateDigest.algorithm.rawValue
    revision.stateDigestValue = stateDigest.hexadecimalValue
    revision.schemaRootDigestAlgorithm = designSchemaBundleDigest.algorithm.rawValue
    revision.schemaRootDigestValue = designSchemaBundleDigest.hexadecimalValue
    revision.dependencyRootDigestAlgorithm = dependencyRoot.algorithm.rawValue
    revision.dependencyRootDigestValue = dependencyRoot.hexadecimalValue
    revision.dependencyLockEntryCount = Int64(directDependencyLock.entries.count)
    revision.dependencyLockEntries = try DesignDatabaseRuntimeDependencyLockDirectory
      .encode(directDependencyLock)
    revision.dependencyGraphDigestAlgorithm = dependencyGraph.algorithm.rawValue
    revision.dependencyGraphDigestValue = dependencyGraph.hexadecimalValue
    revision.facetRootCount = 0
    revision.facetRoots = ""
    revision.projectionDescriptorCount = 1
    revision.projectionDescriptorDigests = projectionDirectory
    revision.directChangeRootDigestAlgorithm = directChangeRoot.algorithm.rawValue
    revision.directChangeRootDigestValue = directChangeRoot.hexadecimalValue
    let revisionLifecycle = try DesignDatabaseRuntimeRevisionLifecycle
      .makeVisible(
        revision: DesignRevisionReference(
          databaseID: request.databaseID,
          revisionID: request.genesisRevisionID
        ),
        reachabilityGeneration: 0,
        using: digester
      )

    var reference = DesignNamedReferenceModel()
    reference.id = "main"
    reference.databaseID = request.databaseID.description
    reference.revisionID = request.genesisRevisionID.description
    reference.generation = 1

    var registration = DesignRuntimeRegistrationModel()
    registration.schemaFingerprintAlgorithm = schemaFingerprint.algorithm.rawValue
    registration.schemaFingerprintValue = schemaFingerprint.hexadecimalValue
    registration.registrationDigestAlgorithm = request.registrationDigest.algorithm.rawValue
    registration.registrationDigestValue = request.registrationDigest.hexadecimalValue
    registration.contributionCount = Int64(contributionCount)

    var reachability = DesignReachabilityStateModel()
    reachability.databaseID = request.databaseID.description

    var identityAllocator = DesignIdentityAllocatorStateModel()
    identityAllocator.id = "active"
    identityAllocator.databaseID = request.databaseID.description

    let schemaBundleID = digestKey(request.initialSchemaBundle.rootDigest)
    var schemaBundle = DesignSchemaBundleModel()
    schemaBundle.id = schemaBundleID
    schemaBundle.rootDigestAlgorithm = request.initialSchemaBundle.rootDigest.algorithm.rawValue
    schemaBundle.rootDigestValue = request.initialSchemaBundle.rootDigest.hexadecimalValue
    schemaBundle.memberCount = Int64(request.initialSchemaBundle.members.count)
    schemaBundle.memberIDs = request.initialSchemaBundle.members
      .map(\.schemaID.rawValue)
      .joined(separator: "\n")
    let schemaBundleMembers = request.initialSchemaBundle.members.map { member in
      var model = DesignSchemaBundleMemberModel()
      model.id = schemaBundleID + ":" + member.schemaID.rawValue
      model.bundleID = schemaBundleID
      model.schemaID = member.schemaID.rawValue
      model.versionMajor = Int64(member.version.major)
      model.versionMinor = Int64(member.version.minor)
      model.versionPatch = Int64(member.version.patch)
      model.canonicalDigestAlgorithm = member.canonicalDigest.algorithm.rawValue
      model.canonicalDigestValue = member.canonicalDigest.hexadecimalValue
      return model
    }

    let capabilities = request.declaredFeatureCapabilities.descriptors.map { descriptor in
      var model = DesignDatabaseCapabilityModel()
      model.id = request.databaseID.description + ":" + descriptor.capabilityID.rawValue
      model.databaseID = request.databaseID.description
      model.capabilityID = descriptor.capabilityID.rawValue
      model.lowerMajor = Int64(descriptor.versions.lowerBound.major)
      model.lowerMinor = Int64(descriptor.versions.lowerBound.minor)
      model.lowerPatch = Int64(descriptor.versions.lowerBound.patch)
      model.upperMajor = Int64(descriptor.versions.upperBound.major)
      model.upperMinor = Int64(descriptor.versions.upperBound.minor)
      model.upperPatch = Int64(descriptor.versions.upperBound.patch)
      return model
    }

    var creation = DesignCreationOperationModel()
    creation.id = operationKey(operation)
    creation.databaseID = request.databaseID.description
    creation.subjectScopeID = request.authorizationSubjectScopeID.description
    creation.operationID = request.operationID.rawValue
    creation.requestDigestAlgorithm = request.requestDigest.algorithm.rawValue
    creation.requestDigestValue = request.requestDigest.hexadecimalValue
    creation.genesisRevisionID = request.genesisRevisionID.description
    creation.outcomeDigestAlgorithm = outcomeDigest.algorithm.rawValue
    creation.outcomeDigestValue = outcomeDigest.hexadecimalValue
    let operationClaim = DesignDatabaseRuntimeOperationClaim.make(
      operation: operation,
      kind: DesignDatabaseRuntimeOperationClaim.creationKind,
      requestDigest: request.requestDigest
    )

    return (
      catalog,
      revision,
      revisionLifecycle,
      reference,
      registration,
      reachability,
      identityAllocator,
      schemaBundle,
      schemaBundleMembers,
      capabilities,
      projection,
      revisionPhysicalIdentityDirectory,
      operationClaim,
      creation
    )
  }

  private static func requireSchemaBundle(
    _ expected: DesignSchemaBundle,
    transaction: DatabaseTransaction
  ) async throws {
    let bundleID = digestKey(expected.rootDigest)
    guard let bundle = try await transaction.fetch(
      DesignSchemaBundleModel.self,
      identifiedBy: bundleID,
      consistency: .serializable
    ), bundle.id == bundleID,
       bundle.rootDigestAlgorithm == expected.rootDigest.algorithm.rawValue,
       bundle.rootDigestValue == expected.rootDigest.hexadecimalValue,
       bundle.memberCount == Int64(expected.members.count),
       bundle.memberIDs == expected.members.map(\.schemaID.rawValue).joined(separator: "\n") else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "The persisted schema bundle does not match the creation request."
      )
    }
    let memberIDs = expected.members.map {
      bundleID + ":" + $0.schemaID.rawValue
    }
    let members = try await transaction.fetch(
      DesignSchemaBundleMemberModel.self,
      identifiedBy: memberIDs,
      consistency: .serializable
    )
    guard members.count == expected.members.count else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "One or more persisted schema bundle members are missing."
      )
    }
    var persistedByID: [String: DesignSchemaBundleMemberModel] = [:]
    for member in members {
      guard persistedByID.updateValue(member, forKey: member.schemaID) == nil else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The persisted schema bundle contains duplicate schema identifiers."
        )
      }
    }
    for member in expected.members {
      guard let persisted = persistedByID[member.schemaID.rawValue],
            persisted.id == bundleID + ":" + member.schemaID.rawValue,
            persisted.bundleID == bundleID,
            persisted.versionMajor == Int64(member.version.major),
            persisted.versionMinor == Int64(member.version.minor),
            persisted.versionPatch == Int64(member.version.patch),
            persisted.canonicalDigestAlgorithm == member.canonicalDigest.algorithm.rawValue,
            persisted.canonicalDigestValue == member.canonicalDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A persisted schema bundle member is inconsistent."
        )
      }
    }
  }

  private static func creationOutcomeDigest(
    request: DesignDatabaseRuntimeGenesisRequest,
    operation: DesignDatabaseOperationReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    try creationOutcomeDigest(
      operation: operation,
      requestDigest: request.requestDigest,
      genesisRevisionID: request.genesisRevisionID.description,
      designSchemaBundleDigest: request.designSchemaBundleDigest,
      registrationDigest: request.registrationDigest,
      using: digester
    )
  }

  private static func creationOutcomeDigest(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    genesisRevisionID: String,
    designSchemaBundleDigest: ContentDigest,
    registrationDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.RuntimeGenesisOutcome"
    )
    encoder.append(operation.databaseID.description)
    encoder.append(operation.authorizationSubjectScopeID.description)
    encoder.append(operation.operationID.rawValue)
    encoder.append(requestDigest)
    encoder.append(genesisRevisionID)
    encoder.append(designSchemaBundleDigest)
    encoder.append(registrationDigest)
    return try encoder.finalize(using: digester)
  }

  private static func digest(
    domain: String,
    values: [String],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(domain: domain)
    for value in values {
      encoder.append(value)
    }
    return try encoder.finalize(using: digester)
  }

  private static func contentDigest(
    algorithm: String,
    value: String
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      return try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: algorithm),
        hexadecimalValue: value
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A persisted runtime digest is malformed."
      )
    }
  }

  private static func operationKey(
    _ operation: DesignDatabaseOperationReference
  ) -> String {
    operation.databaseID.description
      + ":" + operation.authorizationSubjectScopeID.description
      + ":" + operation.operationID.rawValue
  }

  private static func digestKey(_ digest: ContentDigest) -> String {
    digest.algorithm.rawValue + ":" + digest.hexadecimalValue
  }
}
