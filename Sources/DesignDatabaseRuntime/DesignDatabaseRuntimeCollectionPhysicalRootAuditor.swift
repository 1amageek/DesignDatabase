import CircuiteFoundation
import Database
import DesignDatabaseCore

package struct DesignDatabaseRuntimeCollectionPhysicalRootAuditor {
  private let context: DatabaseContext
  private let databaseID: DesignDatabaseID
  private let candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  private let budget: DesignDatabaseRuntimeCollectionRootAuditBudget
  private let digester: any ContentDigesting

  package init(
    context: DatabaseContext,
    databaseID: DesignDatabaseID,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet,
    budget: DesignDatabaseRuntimeCollectionRootAuditBudget,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard candidates.databaseID == databaseID else {
      throw .persistedStateCorrupt(
        reason: "A physical collection root audit crosses a database boundary."
      )
    }
    self.context = context
    self.databaseID = databaseID
    self.candidates = candidates
    self.budget = budget
    self.digester = digester
  }

  package func audit()
    async throws(DesignDatabaseRuntimeError)
      -> DesignDatabaseRuntimeCollectionPhysicalRootAuditResult
  {
    var attempt: UInt64 = 0
    var lastExpected: Int64 = 0
    var lastActual: Int64 = 0
    while attempt < budget.maximumGenerationRetryCount {
      attempt += 1
      let before = try await reachabilityGeneration()
      let buildIntents = try await scanAll(
        DesignCommitBuildIntentModel.self,
        maximumCount: budget.maximumBuildIntentCount,
        kind: "commit build intents"
      )
      let stagingRoots = try await scanAll(
        DesignStagingRootModel.self,
        maximumCount: budget.maximumBuildIntentCount,
        kind: "staging roots"
      )
      let physicalDirectories = try await scanAll(
        DesignStagingPhysicalIdentityDirectoryModel.self,
        maximumCount: budget.maximumBuildIntentCount,
        kind: "staging physical identity directories"
      )
      let manifests = try await scanAll(
        DesignRevisionManifestModel.self,
        maximumCount: budget.maximumManifestCount,
        kind: "revision manifests"
      )
      let revisionPhysicalDirectories = try await scanAll(
        DesignRevisionPhysicalIdentityDirectoryModel.self,
        maximumCount: budget.maximumManifestCount,
        kind: "revision physical identity directories"
      )
      let lifecycles = try await scanAll(
        DesignRevisionLifecycleModel.self,
        maximumCount: budget.maximumManifestCount,
        kind: "revision lifecycles"
      )
      let after = try await reachabilityGeneration()
      guard before == after else {
        lastExpected = before
        lastActual = after
        continue
      }
      return try analyze(
        reachabilityGeneration: after,
        buildIntents: buildIntents,
        stagingRoots: stagingRoots,
        physicalDirectories: physicalDirectories,
        manifests: manifests,
        revisionPhysicalDirectories: revisionPhysicalDirectories,
        lifecycles: lifecycles
      )
    }
    throw .collectionReachabilityChanged(
      expected: lastExpected,
      actual: lastActual
    )
  }

  private func reachabilityGeneration()
    async throws(DesignDatabaseRuntimeError) -> Int64
  {
    do {
      return try await context.withTransaction { transaction in
        try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        ).generation
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func scanAll<Model: Persistable>(
    _ model: Model.Type,
    maximumCount: UInt64,
    kind: String
  ) async throws(DesignDatabaseRuntimeError) -> [Model] {
    var continuation: DatabaseScanContinuation?
    var result: [Model] = []
    var observedCount: UInt64 = 0
    repeat {
      let pageContinuation = continuation
      let page: DesignDatabaseRuntimeReadPage<Model>
      do {
        page = try await context.withTransaction { transaction in
          let scanned = try await transaction.scan(
            model,
            after: pageContinuation,
            limit: budget.scanPageSize
          )
          return DesignDatabaseRuntimeReadPage(
            items: scanned.items,
            continuation: scanned.continuation
          )
        }
      } catch {
        throw .commitTransactionFailed(reason: String(describing: error))
      }
      guard let pageCount = UInt64(exactly: page.items.count) else {
        throw .collectionRootAuditBudgetExceeded(
          kind: kind,
          limit: maximumCount,
          requested: UInt64.max
        )
      }
      let (nextCount, overflow) = observedCount.addingReportingOverflow(
        pageCount
      )
      guard !overflow, nextCount <= maximumCount else {
        throw .collectionRootAuditBudgetExceeded(
          kind: kind,
          limit: maximumCount,
          requested: overflow ? UInt64.max : nextCount
        )
      }
      observedCount = nextCount
      result.append(contentsOf: page.items)
      continuation = page.continuation
    } while continuation != nil
    return result
  }

  private func analyze(
    reachabilityGeneration: Int64,
    buildIntents: [DesignCommitBuildIntentModel],
    stagingRoots: [DesignStagingRootModel],
    physicalDirectories: [DesignStagingPhysicalIdentityDirectoryModel],
    manifests: [DesignRevisionManifestModel],
    revisionPhysicalDirectories:
      [DesignRevisionPhysicalIdentityDirectoryModel],
    lifecycles: [DesignRevisionLifecycleModel]
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionPhysicalRootAuditResult
  {
    let intentByID = try uniqueIndex(
      buildIntents,
      id: \.id,
      kind: "commit build intent"
    )
    let stagingRootByID = try uniqueIndex(
      stagingRoots,
      id: \.id,
      kind: "staging root"
    )
    let physicalDirectoryByID = try uniqueIndex(
      physicalDirectories,
      id: \.id,
      kind: "staging physical identity directory"
    )
    guard Set(stagingRootByID.keys) == Set(intentByID.keys),
          Set(physicalDirectoryByID.keys) == Set(intentByID.keys) else {
      throw .persistedStateCorrupt(
        reason: "Commit build intents, staging roots, and physical identity directories are incomplete."
      )
    }
    let manifestByID = try uniqueIndex(
      manifests,
      id: \.id,
      kind: "revision manifest"
    )
    let lifecycleByID = try uniqueIndex(
      lifecycles,
      id: \.revisionID,
      kind: "revision lifecycle"
    )
    let revisionPhysicalDirectoryByID = try uniqueIndex(
      revisionPhysicalDirectories,
      id: \.revisionID,
      kind: "revision physical identity directory"
    )
    guard Set(manifestByID.keys) == Set(lifecycleByID.keys),
          Set(manifestByID.keys) == Set(revisionPhysicalDirectoryByID.keys)
    else {
      throw .persistedStateCorrupt(
        reason: "Revision manifests, lifecycles, and owned physical identity directories are incomplete."
      )
    }

    let candidateRevisionIDs = Set(
      candidates.revisions.map(\.revisionID.description)
    )
    var foundCandidateRevisionIDs = Set<String>()
    var candidateIdentities = Set<DesignDatabaseRuntimeImmutableWriteIdentity>()
    var protectedIdentities = Set<DesignDatabaseRuntimeImmutableWriteIdentity>()
    var rejectedStagingRootIDs: [String] = []
    var physicalIdentityObservationCount: UInt64 = 0
    var rootTokens: [String] = []

    for revisionID in manifestByID.keys.sorted() {
      guard let manifest = manifestByID[revisionID],
            manifest.databaseID == databaseID.description,
            let lifecycle = lifecycleByID[revisionID],
            let directoryModel = revisionPhysicalDirectoryByID[revisionID]
      else {
        throw .persistedStateCorrupt(
          reason: "A revision physical reachability binding is incomplete."
        )
      }
      let revision = DesignRevisionReference(
        databaseID: databaseID,
        revisionID: try self.revisionID(
          revisionID,
          kind: "revision physical identity directory"
        )
      )
      let lifecycleState = try DesignDatabaseRuntimeRevisionLifecycle.validate(
        lifecycle,
        revision: revision,
        using: digester
      )
      let directory = try
        DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
          model: directoryModel,
          revision: revision,
          using: digester
        )
      let directoryCount = UInt64(directory.identities.count)
      let (nextObservationCount, countOverflow) =
        physicalIdentityObservationCount.addingReportingOverflow(
          directoryCount
        )
      guard !countOverflow,
            nextObservationCount <= budget.maximumPhysicalIdentityCount else {
        throw .collectionRootAuditBudgetExceeded(
          kind: "physical identities",
          limit: budget.maximumPhysicalIdentityCount,
          requested: countOverflow ? UInt64.max : nextObservationCount
        )
      }
      physicalIdentityObservationCount = nextObservationCount

      if candidateRevisionIDs.contains(revisionID) {
        guard lifecycleState == .visible else {
          throw .persistedStateCorrupt(
            reason: "A physical collection candidate is not visible."
          )
        }
        foundCandidateRevisionIDs.insert(revisionID)
        candidateIdentities.formUnion(directory.identities)
      } else {
        switch lifecycleState {
        case .visible, .deleting:
          protectedIdentities.formUnion(directory.identities)
        case .collected:
          break
        }
      }
      rootTokens.append(
        "revision:\(revisionID):\(lifecycleState.rawValue):\(directory.digest.hexadecimalValue)"
      )
    }

    for intent in buildIntents.sorted(by: { $0.id < $1.id }) {
      let binding = try recoverBuildIntentBinding(intent)
      let intentState = try DesignDatabaseRuntimeCommitBuildIntent.validateStatus(
        intent,
        operation: binding.operation,
        requestDigest: binding.requestDigest,
        using: digester
      )
      guard let stagingRoot = stagingRootByID[intent.id],
            let physicalDirectoryModel = physicalDirectoryByID[intent.id] else {
        throw .persistedStateCorrupt(
          reason: "A commit build is missing its physical reachability records."
        )
      }
      let candidateRevision = DesignRevisionReference(
        databaseID: databaseID,
        revisionID: try revisionID(
          intent.candidateRevisionID,
          kind: "commit build candidate"
        )
      )
      let stagingRootState = try DesignDatabaseRuntimeStagingRoot.validateStatus(
        stagingRoot,
        operation: binding.operation,
        requestDigest: binding.requestDigest,
        planDigest: binding.planDigest,
        candidateRevisionID: candidateRevision.revisionID.description,
        stagingDigest: binding.stagingDigest,
        using: digester
      )
      let physicalDirectory = try
        DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
          model: physicalDirectoryModel,
          operation: binding.operation,
          requestDigest: binding.requestDigest,
          planDigest: binding.planDigest,
          candidateRevision: candidateRevision,
          using: digester
        )
      guard try DesignDatabaseRuntimeStagingRoot
        .physicalIdentityDirectoryDigest(stagingRoot)
          == physicalDirectory.digest else {
        throw .persistedStateCorrupt(
          reason: "A staging root does not bind its physical identity directory."
        )
      }
      switch intentState {
      case .committed:
        break
      case .staging, .prepared, .rejected:
        let directoryCount = UInt64(physicalDirectory.identities.count)
        let (nextObservationCount, countOverflow) =
          physicalIdentityObservationCount.addingReportingOverflow(
            directoryCount
          )
        guard !countOverflow,
              nextObservationCount
                <= budget.maximumPhysicalIdentityCount else {
          throw .collectionRootAuditBudgetExceeded(
            kind: "physical identities",
            limit: budget.maximumPhysicalIdentityCount,
            requested: countOverflow ? UInt64.max : nextObservationCount
          )
        }
        physicalIdentityObservationCount = nextObservationCount
      }

      switch intentState {
      case .staging, .prepared:
        guard stagingRootState == .active,
              manifestByID[candidateRevision.revisionID.description] == nil else {
          throw .persistedStateCorrupt(
            reason: "A nonterminal commit build has a terminal root or published revision."
          )
        }
        protectedIdentities.formUnion(physicalDirectory.identities)
      case .committed:
        guard stagingRootState == .published,
              let manifest = manifestByID[candidateRevision.revisionID.description],
              manifest.databaseID == databaseID.description,
              let revisionDirectoryModel = revisionPhysicalDirectoryByID[
                candidateRevision.revisionID.description
              ]
        else {
          throw .persistedStateCorrupt(
            reason: "A committed build has no published revision physical directory."
          )
        }
        let revisionDirectory = try
          DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
            model: revisionDirectoryModel,
            revision: candidateRevision,
            using: digester
          )
        guard revisionDirectory.identities == physicalDirectory.identities else {
          throw .persistedStateCorrupt(
            reason: "A committed build does not match its revision-owned physical identity directory."
          )
        }
      case .rejected:
        guard stagingRootState == .rejected
                || stagingRootState == .reclaiming
                || stagingRootState == .reclaimed else {
          throw .persistedStateCorrupt(
            reason: "A rejected commit build has an incompatible staging root."
          )
        }
        switch stagingRootState {
        case .rejected:
          candidateIdentities.formUnion(physicalDirectory.identities)
          rejectedStagingRootIDs.append(stagingRoot.id)
        case .reclaiming:
          protectedIdentities.formUnion(physicalDirectory.identities)
        case .reclaimed:
          break
        case .active, .published:
          throw .persistedStateCorrupt(
            reason: "A rejected commit build has an incompatible staging root."
          )
        }
      }
      rootTokens.append(
        "build:\(intent.id):\(intent.candidateRevisionID):\(intent.state):\(stagingRoot.reachabilityGeneration):\(physicalDirectory.digest.hexadecimalValue)"
      )
    }

    let missingCandidates = candidateRevisionIDs.subtracting(
      foundCandidateRevisionIDs
    )
    guard missingCandidates.isEmpty else {
      throw .physicalIdentityDirectoryNotFound(
        revisionID: missingCandidates.sorted()[0]
      )
    }
    let claimedIdentities = candidateIdentities
      .subtracting(protectedIdentities)
      .sorted()
    guard UInt64(claimedIdentities.count) <= budget.maximumPhysicalClaimCount else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "physical collection claims",
        limit: budget.maximumPhysicalClaimCount,
        requested: UInt64(claimedIdentities.count)
      )
    }
    let claimSetDigest = try DesignDatabaseRuntimePhysicalCollectionClaim
      .identitySetDigest(claimedIdentities, using: digester)
    let protected = protectedIdentities.sorted()
    guard let generation = UInt64(exactly: reachabilityGeneration),
          let protectedCount = UInt64(exactly: protected.count),
          let tokenCount = UInt64(exactly: rootTokens.count) else {
      throw .persistedStateCorrupt(
        reason: "A physical root audit count or generation is invalid."
      )
    }
    rootTokens.sort()
    rejectedStagingRootIDs.sort()
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CollectionPhysicalRootSet"
    )
    encoder.append(databaseID.description)
    encoder.append(generation)
    encoder.append(tokenCount)
    for token in rootTokens { encoder.append(token) }
    encoder.append(protectedCount)
    for identity in protected { encoder.append(identity.canonicalBytes) }
    encoder.append(UInt64(rejectedStagingRootIDs.count))
    for rootID in rejectedStagingRootIDs { encoder.append(rootID) }
    encoder.append(claimSetDigest)
    return DesignDatabaseRuntimeCollectionPhysicalRootAuditResult(
      observedReachabilityGeneration: reachabilityGeneration,
      rootSetDigest: try encoder.finalize(using: digester),
      claimSetDigest: claimSetDigest,
      claimedIdentities: claimedIdentities,
      rejectedStagingRootIDs: rejectedStagingRootIDs,
      protectedIdentityCount: protectedCount
    )
  }

  private func recoverBuildIntentBinding(
    _ model: DesignCommitBuildIntentModel
  ) throws(DesignDatabaseRuntimeError) -> (
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    stagingDigest: ContentDigest
  ) {
    do {
      let operation = DesignDatabaseOperationReference(
        databaseID: try DesignDatabaseID(hexadecimalValue: model.databaseID),
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: model.subjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(rawValue: model.operationID)
      )
      guard operation.databaseID == databaseID,
            model.id == DesignDatabaseRuntimeOperationClaim.key(operation) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A physical root build intent crosses its database or operation boundary."
        )
      }
      return (
        operation,
        try ContentDigest(
          algorithm: ContentDigestAlgorithm(rawValue: model.requestDigestAlgorithm),
          hexadecimalValue: model.requestDigestValue
        ),
        try ContentDigest(
          algorithm: ContentDigestAlgorithm(rawValue: model.planDigestAlgorithm),
          hexadecimalValue: model.planDigestValue
        ),
        try ContentDigest(
          algorithm: ContentDigestAlgorithm(rawValue: model.stagingDigestAlgorithm),
          hexadecimalValue: model.stagingDigestValue
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A physical root build intent has a malformed identity or digest."
      )
    }
  }

  private func revisionID(
    _ value: String,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionID {
    do {
      return try DesignRevisionID(hexadecimalValue: value)
    } catch {
      throw .persistedStateCorrupt(
        reason: "A \(kind) revision identity is malformed."
      )
    }
  }

  private func uniqueIndex<Model>(
    _ models: [Model],
    id: KeyPath<Model, String>,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> [String: Model] {
    var result: [String: Model] = [:]
    for model in models {
      let identifier = model[keyPath: id]
      guard !identifier.isEmpty, result[identifier] == nil else {
        throw .persistedStateCorrupt(
          reason: "A \(kind) has an empty or duplicate identity."
        )
      }
      result[identifier] = model
    }
    return result
  }
}
