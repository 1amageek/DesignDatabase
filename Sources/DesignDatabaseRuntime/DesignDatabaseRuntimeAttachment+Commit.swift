import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import Foundation

extension DesignDatabaseRuntimeAttachment {
  package func submit(
    _ submission: DesignCommitSubmission,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitResult {
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    let candidateRevision = try Self.candidateRevision(
      operation: operation,
      requestDigest: submission.requestDigest
    )

    let isInProgressRetry: Bool
    switch try await commitStatus(
      operation: operation,
      requestDigest: submission.requestDigest,
      digester: digester
    ) {
    case .committed(let receipt):
      return .committed(receipt)
    case .rejected(let rejection):
      return .rejected(rejection)
    case .notRecorded:
      isInProgressRetry = false
      break
    case .inProgress:
      isInProgressRetry = true
      break
    case .outcomeUnknown(let unknown):
      return .outcomeUnknown(unknown)
    }

    let preflight = try await inspectCommitBase(
      submission,
      candidateRevision: candidateRevision,
      databaseID: databaseID,
      digester: digester
    )
    if let rejectionReason = preflight.rejectionReason {
      return try await recordCommitRejection(
        operation: operation,
        submission: submission,
        reason: rejectionReason,
        using: digester
      )
    }
    guard let baseProjectionState = preflight.baseProjectionState else {
      throw .persistedStateCorrupt(
        reason: "An accepted commit base has no projection state."
      )
    }
    guard let baseDependencyLock = preflight.baseDependencyLock else {
      throw .persistedStateCorrupt(
        reason: "An accepted commit base has no direct dependency lock."
      )
    }
    let candidateDependencyLock = submission.plan.dependencyLockUpdate?
      .replacement ?? baseDependencyLock
    let candidateDependencyRootDigest = submission.plan.dependencyLockUpdate?
      .dependencyRootDigest ?? submission.plan.dependencyRootDigest
    let candidateSemanticDependencyGraphDigest = submission.plan
      .dependencyLockUpdate?.semanticDependencyGraphDigest
      ?? submission.plan.semanticDependencyGraphDigest

    let databaseContext = try context()
    let validationContext = DesignDatabaseRuntimeMutationValidation(
      databaseID: databaseID,
      baseRevision: submission.plan.baseRevision,
      candidateRevision: candidateRevision,
      designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
      directDependencyLock: candidateDependencyLock,
      dependencyRootDigest: candidateDependencyRootDigest,
      semanticDependencyGraphDigest: candidateSemanticDependencyGraphDigest,
      baseFacetRoots: preflight.baseFacetRoots,
      budget: submission.plan.budget,
      reads: DesignDatabaseRuntimeReadSnapshot(
        context: databaseContext,
        revision: submission.plan.baseRevision,
        maximumReadCount: submission.plan.budget.maximumValidationReadCount
      ),
      projectionReader: DesignProjectionTreeReader(
        context: databaseContext,
        decodedPageCache: decodedProjectionPageCache,
        revision: submission.plan.baseRevision,
        designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
        descriptors: baseProjectionState.descriptors,
        descriptorDigests: baseProjectionState.descriptorDigests,
        bindings: baseProjectionState.bindings
      )
    )

    var adapters: [any DesignDatabaseRuntimeMutationAdapter] = []
    adapters.reserveCapacity(submission.plan.segments.count)
    var targetFacets: Set<DesignFacetID> = []
    for segment in submission.plan.segments {
      guard targetFacets.insert(segment.targetFacet).inserted else {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .invalidSegmentPayload(
            segmentID: segment.id,
            reason: "A candidate plan must provide exactly one prepared root per target facet."
          ),
          using: digester
        )
      }
      guard let adapter = mutationAdapters[segment.schemaID],
            adapter.schemaVersion == segment.schemaVersion,
            adapter.adapterVersion == segment.adapterVersion,
            adapter.supportedFacets.contains(segment.targetFacet) else {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .adapterUnavailable(
            schemaID: segment.schemaID,
            adapterVersion: segment.adapterVersion
          ),
          using: digester
        )
      }
      adapters.append(adapter)
    }

    let validatedDirectory: DesignDatabaseRuntimeValidatedMutationDirectory
    if isInProgressRetry {
      validatedDirectory = try await validatedMutationDirectory(
        operation: operation,
        submission: submission,
        digester: digester
      )
    } else {
      var validations: [DesignDatabaseRuntimeValidatedMutation] = []
      validations.reserveCapacity(submission.plan.segments.count)
      for (segment, adapter) in zip(submission.plan.segments, adapters) {
        do {
          validations.append(
            try await DesignDatabaseRuntimeStorageSecurity
              .withUnprivilegedAccess {
                try await adapter.validate(segment, in: validationContext)
              }
          )
        } catch let error as DesignDatabaseRuntimeMutationAdapterError {
          let reason: DesignCommitRejection.Reason
          switch error {
          case .invalidPayload(let detail):
            reason = .invalidSegmentPayload(
              segmentID: segment.id,
              reason: detail
            )
          case .validationFailed(let diagnostics, let diagnosticsDigest):
            reason = .validationFailed(
              diagnostics: diagnostics,
              diagnosticsDigest: diagnosticsDigest
            )
          case .budgetExceeded(let limit, let requested):
            reason = .budgetExceeded(limit: limit, requested: requested)
          }
          return try await recordCommitRejection(
            operation: operation,
            submission: submission,
            reason: reason,
            using: digester
          )
        } catch {
          throw .commitTransactionFailed(
            reason: "A validation adapter escaped its typed failure contract: \(error)"
          )
        }
      }
      do {
        validatedDirectory = try DesignDatabaseRuntimeValidatedMutationDirectory(
          segments: submission.plan.segments,
          validations: validations,
          using: digester
        )
      } catch .validatedMutationDirectoryBudgetExceeded(let limit, let requested) {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .budgetExceeded(limit: limit, requested: requested),
          using: digester
        )
      }
    }

    let reservedIdentities: DesignDatabaseRuntimeReservedIdentities
    do {
      reservedIdentities = try await reserveIdentities(
        operation: operation,
        submission: submission,
        validatedDirectory: validatedDirectory,
        digester: digester
      )
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignCommitUnknown(
          operation: operation,
          requestDigest: submission.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }

    let restoration = DesignDatabaseRuntimeMutationRestoration(
      databaseID: databaseID,
      baseRevision: submission.plan.baseRevision,
      candidateRevision: candidateRevision,
      designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
      directDependencyLock: candidateDependencyLock,
      dependencyRootDigest: candidateDependencyRootDigest,
      semanticDependencyGraphDigest: candidateSemanticDependencyGraphDigest,
      baseFacetRoots: preflight.baseFacetRoots,
      identityAssignmentsBySegment: reservedIdentities.assignments
    )
    let persistedPreparedDirectory = isInProgressRetry
      ? try await preparedMutationDirectory(
          operation: operation,
          submission: submission,
          digester: digester
        )
      : nil
    var prepared: [any DesignDatabaseRuntimePreparedMutation] = []
    prepared.reserveCapacity(submission.plan.segments.count)
    var preparedFacetRoots: [DesignFacetRoot] = []
    preparedFacetRoots.reserveCapacity(submission.plan.segments.count)
    var preparedWriteCount: UInt64 = 0

    for (segmentIndex, segment) in submission.plan.segments.enumerated() {
      let adapter = adapters[segmentIndex]
      let validation = validatedDirectory.records[segmentIndex]
      let mutation: any DesignDatabaseRuntimePreparedMutation
      do {
        mutation = try DesignDatabaseRuntimeStorageSecurity
          .withUnprivilegedAccess {
            try adapter.materializeValidatedMutation(
              validation,
              for: segment,
              in: restoration
            )
          }
        if let persistedPreparedDirectory {
          try persistedPreparedDirectory.records[segmentIndex].validate(
            segment: segment,
            mutation: mutation
          )
        }
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .persistedStateCorrupt(
          reason: "A domain adapter could not materialize its persisted validated input: \(error)"
        )
      }

      guard mutation.segmentID == segment.id,
            mutation.writeCount > 0,
            mutation.writeCount <= segment.expectedWriteCount else {
        throw .persistedStateCorrupt(
          reason: "A mutation adapter returned a prepared write set that violates its segment contract."
        )
      }
      let (nextCount, overflow) = preparedWriteCount.addingReportingOverflow(
        mutation.writeCount
      )
      guard !overflow else {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .budgetExceeded(
            limit: submission.plan.budget.maximumPreparedWriteCount,
            requested: UInt64.max
          ),
          using: digester
        )
      }
      preparedWriteCount = nextCount
      guard preparedWriteCount
        <= submission.plan.budget.maximumPreparedWriteCount else {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .budgetExceeded(
            limit: submission.plan.budget.maximumPreparedWriteCount,
            requested: preparedWriteCount
          ),
          using: digester
        )
      }
      prepared.append(mutation)
      do {
        preparedFacetRoots.append(
          try DesignFacetRoot(
            facetID: segment.targetFacet,
            digest: mutation.facetRootDigest
          )
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A mutation adapter returned an invalid facet root."
        )
      }
    }

    let preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory
    if let persistedPreparedDirectory {
      preparedDirectory = persistedPreparedDirectory
    } else {
      do {
        preparedDirectory = try DesignDatabaseRuntimePreparedMutationDirectory(
          segments: submission.plan.segments,
          prepared: prepared,
          using: digester
        )
      } catch .preparedMutationDirectoryBudgetExceeded(
        let limit,
        let requested
      ) {
        return try await recordCommitRejection(
          operation: operation,
          submission: submission,
          reason: .budgetExceeded(limit: limit, requested: requested),
          using: digester
        )
      }
    }

    let candidateFacetRoots = try DesignDatabaseRuntimeFacetRootDirectory.replacing(
      preflight.baseFacetRoots,
      with: preparedFacetRoots
    )
    let facetProjectionEntries: [DesignProjectionEntry]
    do {
      facetProjectionEntries = try candidateFacetRoots.map { root in
        try DesignFacetProjectionRecord(
          facetID: root.facetID,
          rootDigest: root.digest
        ).projectionEntry()
      }
    } catch {
      throw .persistedStateCorrupt(
        reason: "Candidate facet roots could not form a semantic projection."
      )
    }
    let facetProjection = try DesignProjectionTreeBuilder().build(
      family: .facet,
      entries: facetProjectionEntries,
      digester: digester
    )
    let candidateProjectionPlan: DesignDatabaseRuntimeCandidateProjectionPlan
    switch try await DesignDatabaseRuntimeCandidateProjectionPlanner.plan(
      facetProjection: facetProjection,
      base: baseProjectionState,
      prepared: prepared,
      identityAssignments: reservedIdentities.assignments,
      reads: validationContext.reads,
      using: digester
    ) {
    case .planned(let plan):
      candidateProjectionPlan = plan
    case .rejected(let reason):
      return try await recordCommitRejection(
        operation: operation,
        submission: submission,
        reason: reason,
        using: digester
      )
    }
    let projectionStaging = try DesignDatabaseRuntimeProjectionStagingDirectory(
      candidateProjectionPlan.materializations,
      databaseID: databaseID,
      revision: candidateRevision
    )
    let projectionDirectory = try DesignDatabaseRuntimeProjectionDirectory.encode(
      projectionStaging.materializations
    )
    let stateDigest = try DesignDatabaseRuntimeFacetRootDirectory.stateDigest(
      designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
      dependencyRootDigest: candidateDependencyRootDigest,
      semanticDependencyGraphDigest: candidateSemanticDependencyGraphDigest,
      facetRoots: candidateFacetRoots,
      projectionSemantics: projectionStaging.descriptors,
      using: digester
    )
    let changeSetDigest = try Self.aggregateChangeSetDigest(
      plan: submission.plan,
      prepared: prepared,
      projectionPlan: candidateProjectionPlan,
      using: digester
    )
    let outcomeDigest: ContentDigest
    do {
      outcomeDigest = try DesignMutationPlanDigest.committedOutcome(
        operation: operation,
        requestDigest: submission.requestDigest,
        planDigest: submission.plan.planDigest,
        baseRevision: submission.plan.baseRevision,
        candidateRevision: candidateRevision,
        stateDigest: stateDigest,
        changeSetDigest: changeSetDigest,
        designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
        dependencyRootDigest: candidateDependencyRootDigest,
        semanticDependencyGraphDigest: candidateSemanticDependencyGraphDigest,
        facetRoots: candidateFacetRoots,
        using: digester
      )
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    let receipt = DesignCommitReceipt(
      operation: operation,
      requestDigest: submission.requestDigest,
      planDigest: submission.plan.planDigest,
      baseRevision: submission.plan.baseRevision,
      candidateRevision: candidateRevision,
      stateDigest: stateDigest,
      changeSetDigest: changeSetDigest,
      designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
      dependencyRootDigest: candidateDependencyRootDigest,
      semanticDependencyGraphDigest: candidateSemanticDependencyGraphDigest,
      facetRoots: candidateFacetRoots,
      outcomeDigest: outcomeDigest
    )

    let preparedWriteDirectory = try DesignDatabaseRuntimePreparedWriteDirectory(
      prepared
    )
    let projectionNodeCount = projectionStaging.totalNodeCount
    let physicalIdentityDirectory = try
      DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
        preparedDirectory: preparedDirectory,
        projections: projectionStaging,
        using: digester
      )
    let revisionPhysicalIdentityDirectory = try
      DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
        revision: candidateRevision,
        identities: physicalIdentityDirectory.identities,
        using: digester
      ).model()
    let stagingDigest = try DesignDatabaseRuntimeCommitBuildIntent.stagingDigest(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectory: preparedDirectory,
      prepared: prepared,
      projectionPlan: candidateProjectionPlan,
      projections: projectionStaging,
      physicalIdentityDirectory: physicalIdentityDirectory,
      using: digester
    )
    let shouldStage = try await ensureCommitBuildIntent(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectory: preparedDirectory,
      physicalIdentityDirectory: physicalIdentityDirectory,
      stagingDigest: stagingDigest,
      preparedWriteCount: preparedWriteDirectory.totalWriteCount,
      projectionNodeCount: projectionNodeCount,
      digester: digester
    )
    if shouldStage {
      try await stageCommitBuild(
        operation: operation,
        submission: submission,
        candidateRevision: candidateRevision,
        preparedDirectory: preparedDirectory,
        stagingDigest: stagingDigest,
        prepared: prepared,
        projections: projectionStaging,
        digester: digester
      )
    }

    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let key = DesignDatabaseRuntimeOperationClaim.key(operation)
        let existingClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingOutcome = try await transaction.fetch(
          DesignCommitOperationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingIntent = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingStagingRoot = try await transaction.fetch(
          DesignStagingRootModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingPhysicalIdentityDirectory = try await transaction.fetch(
          DesignStagingPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        if let existingClaim {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            existingClaim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
              operation: key
            )
          }
          if let existingOutcome {
            return try Self.commitResult(
              model: existingOutcome,
              operation: operation,
              requestDigest: submission.requestDigest,
              using: digester
            )
          }
        } else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A prepared commit build has no operation claim."
          )
        }
        guard existingOutcome == nil, let existingIntent else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A prepared commit build has no persisted intent."
          )
        }
        let intentState = try DesignDatabaseRuntimeCommitBuildIntent.validate(
          existingIntent,
          operation: operation,
          submission: submission,
          candidateRevision: candidateRevision,
          preparedDirectoryDigest: preparedDirectory.digest,
          preparedMutationCount: UInt64(preparedDirectory.records.count),
          stagingDigest: stagingDigest,
          expectedDomainWriteCount: preparedWriteDirectory.totalWriteCount,
          expectedProjectionNodeCount: projectionNodeCount,
          using: digester
        )
        guard intentState == .prepared else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit build reached publication before staging completed."
          )
        }
        guard let existingStagingRoot else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A prepared commit build has no active staging root."
          )
        }
        guard let existingPhysicalIdentityDirectory else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A prepared commit build has no physical identity directory."
          )
        }
        try DesignDatabaseRuntimeStagingRoot.validate(
          existingStagingRoot,
          operation: operation,
          submission: submission,
          candidateRevision: candidateRevision,
          stagingDigest: stagingDigest,
          expectedState: .active,
          using: digester
        )
        let restoredPhysicalIdentityDirectory = try
          DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
            model: existingPhysicalIdentityDirectory,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            using: digester
          )
        guard restoredPhysicalIdentityDirectory.digest
                == physicalIdentityDirectory.digest,
              restoredPhysicalIdentityDirectory.identities
                == physicalIdentityDirectory.identities,
              try DesignDatabaseRuntimeStagingRoot
                .physicalIdentityDirectoryDigest(existingStagingRoot)
                == physicalIdentityDirectory.digest else {
          throw DesignDatabaseRuntimeError.commitStagingConflict(
            operation: key
          )
        }
        let reachability = try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        )
        let updatedReachability = try DesignDatabaseRuntimeReachability.advanced(
          reachability,
          kind: "reachability"
        )

        guard let base = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: submission.plan.baseRevision.revisionID.description,
          consistency: .serializable
        ), base.databaseID == databaseID.description else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "An immutable base revision disappeared after commit preparation."
          )
        }
        if let existingCandidate = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: candidateRevision.revisionID.description,
          consistency: .serializable
        ) {
          guard existingCandidate.databaseID == databaseID.description else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A candidate revision identity crossed a database boundary."
            )
          }
          let rejection = try Self.commitRejection(
            operation: operation,
            submission: submission,
            reason: .candidateRevisionCollision(candidateRevision),
            using: digester
          )
          let rejectedIntent = try DesignDatabaseRuntimeCommitBuildIntent
            .advanced(
              existingIntent,
              state: .rejected,
              using: digester
            )
          let rejectedStagingRoot = try DesignDatabaseRuntimeStagingRoot
            .terminalized(
              existingStagingRoot,
              state: .rejected,
              reachabilityGeneration: updatedReachability.generation,
              using: digester
            )
          try await transaction.save(rejectedIntent, precondition: .exists)
          try await transaction.save(
            rejectedStagingRoot,
            precondition: .exists
          )
          try await transaction.save(
            updatedReachability,
            precondition: .exists
          )
          try await transaction.save(
            try Self.commitOperationModel(rejection: rejection),
            precondition: .notExists
          )
          return .rejected(rejection)
        }

        for projectionEntry in projectionStaging.entries {
          let projection = projectionEntry.materialization
          try await DesignDatabaseRuntimePhysicalCollectionClaim
            .requireUnclaimed(
              try DesignDatabaseRuntimePhysicalCollectionClaim
                .projectionDescriptorIdentity(
                  projectionEntry.models.descriptor
                ),
              transaction: transaction,
              using: digester
            )
          try await DesignDatabaseRuntimePhysicalCollectionClaim
            .requireUnclaimed(
              try DesignDatabaseRuntimePhysicalCollectionClaim
                .projectionBindingIdentity(
                  projectionEntry.models.binding
                ),
              transaction: transaction,
              using: digester
            )
          try await DesignDatabaseRuntimePhysicalCollectionClaim
            .requireUnclaimed(
              try DesignDatabaseRuntimePhysicalCollectionClaim
                .projectionMaterializationIdentity(
                  projectionEntry.models.materialization
                ),
              transaction: transaction,
              using: digester
            )
          guard let rootModel = try await transaction.fetch(
            DesignProjectionNodeModel.self,
            identifiedBy: DesignProjectionTreeMaterialization.digestKey(
              projection.reference.rootNodeDigest
            ),
            consistency: .serializable
          ) else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A staged projection root disappeared before publication."
            )
          }
          _ = try DesignProjectionPersistedNodeDecoder.decode(
            rootModel,
            expectedDigest: projection.reference.rootNodeDigest,
            family: projection.descriptor.family,
            reference: projection.reference,
            digester: digester
          )
          try await transaction.save(
            projectionEntry.models.descriptor,
            precondition: .notExists
          )
          try await transaction.save(
            projectionEntry.models.materialization,
            precondition: .notExists
          )
          try await transaction.save(
            projectionEntry.models.binding,
            precondition: .notExists
          )
        }
        guard let projectionDescriptorCount = Int64(
          exactly: projectionStaging.entries.count
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A projection descriptor count is not representable."
          )
        }
        let candidateLifecycle = try DesignDatabaseRuntimeRevisionLifecycle
          .makeVisible(
            revision: candidateRevision,
            reachabilityGeneration: updatedReachability.generation,
            using: digester
          )
        try await transaction.save(
          revisionPhysicalIdentityDirectory,
          precondition: .notExists
        )
        try await transaction.save(
          try Self.revisionManifestModel(
            receipt,
            directDependencyLock: candidateDependencyLock,
            projectionDescriptorCount: projectionDescriptorCount,
            projectionDirectory: projectionDirectory
          ),
          precondition: .notExists
        )
        try await transaction.save(
          candidateLifecycle,
          precondition: .notExists
        )
        let committedIntent = try DesignDatabaseRuntimeCommitBuildIntent
          .advanced(
            existingIntent,
            state: .committed,
            using: digester
          )
        let publishedStagingRoot = try DesignDatabaseRuntimeStagingRoot
          .terminalized(
            existingStagingRoot,
            state: .published,
            reachabilityGeneration: updatedReachability.generation,
            using: digester
          )
        try await transaction.save(
          committedIntent,
          precondition: .exists
        )
        try await transaction.save(
          publishedStagingRoot,
          precondition: .exists
        )
        try await transaction.save(
          updatedReachability,
          precondition: .exists
        )
        try await transaction.save(
          try Self.commitOperationModel(receipt: receipt),
          precondition: .notExists
        )
        return .committed(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignCommitUnknown(
          operation: operation,
          requestDigest: submission.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func validatedMutationDirectory(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeValidatedMutationDirectory
  {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      return try await databaseContext.withTransaction { transaction in
        guard let reservation = try await transaction.fetch(
          DesignIdentityReservationModel.self,
          identifiedBy: key,
          consistency: .serializable
        ), let model = try await transaction.fetch(
          DesignValidatedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "An active commit has no atomic validated input and identity reservation."
          )
        }
        let directory = try DesignDatabaseRuntimeValidatedMutationDirectory(
          model: model,
          operation: operation,
          submission: submission,
          using: digester
        )
        try Self.validateIdentityReservationStatus(
          reservation,
          operation: operation,
          requestDigest: submission.requestDigest,
          validatedDirectoryDigest: directory.digest,
          validatedMutationCount: UInt64(directory.records.count)
        )
        return directory
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func preparedMutationDirectory(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimePreparedMutationDirectory?
  {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      return try await databaseContext.withTransaction { transaction in
        let intent = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let model = try await transaction.fetch(
          DesignPreparedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        switch (intent, model) {
        case (nil, nil):
          return nil
        case (.some, nil), (nil, .some):
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit build intent and its prepared mutation directory are incomplete."
          )
        case (.some(let intent), .some(let model)):
          let candidateRevision = try Self.candidateRevision(
            operation: operation,
            requestDigest: submission.requestDigest
          )
          let state = try DesignDatabaseRuntimeCommitBuildIntent.validateStored(
            intent,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            using: digester
          )
          guard state == .staging || state == .prepared else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit build intent entered prepared-input restoration."
            )
          }
          let directory = try DesignDatabaseRuntimePreparedMutationDirectory(
            model: model,
            operation: operation,
            submission: submission,
            using: digester
          )
          guard intent.preparedDirectoryDigestAlgorithm
                  == directory.digest.algorithm.rawValue,
                intent.preparedDirectoryDigestValue
                  == directory.digest.hexadecimalValue,
                intent.preparedMutationCount
                  == UInt64(directory.records.count) else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A prepared mutation directory does not match its build intent."
            )
          }
          return directory
        }
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  package func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitStatus {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      return try await databaseContext.withTransaction { transaction in
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let outcome = try await transaction.fetch(
          DesignCommitOperationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let intent = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let stagingRoot = try await transaction.fetch(
          DesignStagingRootModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let physicalIdentityDirectory = try await transaction.fetch(
          DesignStagingPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let preparedDirectory = try await transaction.fetch(
          DesignPreparedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let validatedDirectory = try await transaction.fetch(
          DesignValidatedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let identityReservation = try await transaction.fetch(
          DesignIdentityReservationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let submissionCapsule = try await transaction.fetch(
          DesignCommitSubmissionModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        guard claim != nil || outcome != nil || intent != nil
          || identityReservation != nil || preparedDirectory != nil
          || validatedDirectory != nil || submissionCapsule != nil
          || stagingRoot != nil || physicalIdentityDirectory != nil else {
          return .notRecorded
        }
        guard let claim else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit outcome or build intent exists without its operation claim."
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          claim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.commitKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
            operation: key
          )
        }
        let recoveredSubmission: DesignCommitSubmission?
        switch (identityReservation, validatedDirectory, submissionCapsule) {
        case (
          .some(let identityReservation),
          .some(let validatedDirectory),
          .some(let submissionCapsule)
        ):
          let validatedDigest: ContentDigest
          do {
            validatedDigest = try ContentDigest(
              algorithm: ContentDigestAlgorithm(
                rawValue: identityReservation.validatedDirectoryDigestAlgorithm
              ),
              hexadecimalValue: identityReservation.validatedDirectoryDigestValue
            )
          } catch {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "An identity reservation has an invalid validated directory digest."
            )
          }
          try Self.validateIdentityReservationStatus(
            identityReservation,
            operation: operation,
            requestDigest: requestDigest,
            validatedDirectoryDigest: validatedDigest,
            validatedMutationCount: identityReservation.validatedMutationCount
          )
          try DesignDatabaseRuntimeValidatedMutationDirectory.validateStatus(
            validatedDirectory,
            operation: operation,
            requestDigest: requestDigest,
            expectedDigest: validatedDigest,
            expectedRecordCount: identityReservation.validatedMutationCount,
            using: digester
          )
          recoveredSubmission = try DesignDatabaseRuntimeCommitSubmissionCapsule(
            model: submissionCapsule,
            operation: operation,
            expectedRequestDigest: requestDigest,
            expectedPlanDigest: try Self.contentDigest(
              algorithm: identityReservation.planDigestAlgorithm,
              value: identityReservation.planDigestValue
            ),
            using: digester
          ).submission
        case (nil, nil, nil):
          recoveredSubmission = nil
        default:
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit submission, validated mutation directory, and identity reservation are not atomic."
          )
        }
        let stagingRootState: DesignDatabaseRuntimeStagingRootState?
        if let intent {
          guard let preparedDirectory else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has no prepared mutation directory."
            )
          }
          let preparedDigest: ContentDigest
          do {
            preparedDigest = try ContentDigest(
              algorithm: ContentDigestAlgorithm(
                rawValue: intent.preparedDirectoryDigestAlgorithm
              ),
              hexadecimalValue: intent.preparedDirectoryDigestValue
            )
          } catch {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has an invalid prepared directory digest."
            )
          }
          try DesignDatabaseRuntimePreparedMutationDirectory.validateStatus(
            preparedDirectory,
            operation: operation,
            requestDigest: requestDigest,
            expectedDigest: preparedDigest,
            expectedRecordCount: intent.preparedMutationCount,
            using: digester
          )
          guard let stagingRoot, let physicalIdentityDirectory,
                let recoveredSubmission else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has no recoverable staging root and physical identity directory."
            )
          }
          let candidateRevision: DesignRevisionReference
          do {
            candidateRevision = DesignRevisionReference(
              databaseID: operation.databaseID,
              revisionID: try DesignRevisionID(
                hexadecimalValue: intent.candidateRevisionID
              )
            )
          } catch {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent candidate revision is malformed."
            )
          }
          stagingRootState = try DesignDatabaseRuntimeStagingRoot.validate(
            stagingRoot,
            operation: operation,
            submission: recoveredSubmission,
            candidateRevision: candidateRevision,
            stagingDigest: try Self.contentDigest(
              algorithm: intent.stagingDigestAlgorithm,
              value: intent.stagingDigestValue
            ),
            using: digester
          )
          let restoredPhysicalIdentityDirectory = try
            DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
              model: physicalIdentityDirectory,
              operation: operation,
              submission: recoveredSubmission,
              candidateRevision: candidateRevision,
              using: digester
            )
          guard try DesignDatabaseRuntimeStagingRoot
            .physicalIdentityDirectoryDigest(stagingRoot)
              == restoredPhysicalIdentityDirectory.digest else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A staging root does not bind its physical identity directory."
            )
          }
        } else if preparedDirectory != nil || stagingRoot != nil
          || physicalIdentityDirectory != nil {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A staging directory or root exists without its commit build intent."
          )
        } else {
          stagingRootState = nil
        }
        if outcome == nil {
          guard identityReservation != nil, submissionCapsule != nil else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "An active commit has no permanent identity reservation and exact submission capsule."
            )
          }
          guard let intent else { return .inProgress }
          let state = try DesignDatabaseRuntimeCommitBuildIntent.validateStatus(
            intent,
            operation: operation,
            requestDigest: requestDigest,
            using: digester
          )
          guard state == .staging || state == .prepared else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit build intent has no outcome."
            )
          }
          guard stagingRootState == .active else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A nonterminal commit build has a terminal staging root."
            )
          }
          return .inProgress
        }
        guard let outcome else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit outcome disappeared during status inspection."
          )
        }
        let intentState: DesignCommitBuildIntentState?
        if let intent {
          intentState = try DesignDatabaseRuntimeCommitBuildIntent.validateStatus(
            intent,
            operation: operation,
            requestDigest: requestDigest,
            using: digester
          )
          guard intentState == .committed || intentState == .rejected else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit outcome has a nonterminal build intent."
            )
          }
        } else {
          intentState = nil
        }
        switch try Self.commitResult(
          model: outcome,
          operation: operation,
          requestDigest: requestDigest,
          using: digester
        ) {
        case .committed(let receipt):
          guard identityReservation != nil,
                intentState == nil || intentState == .committed,
                stagingRootState == nil || stagingRootState == .published else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A committed outcome has no identity reservation or is paired with a rejected build intent."
            )
          }
          return .committed(receipt)
        case .rejected(let rejection):
          guard intentState == nil || intentState == .rejected,
                stagingRootState == nil
                  || stagingRootState == .rejected
                  || stagingRootState == .reclaiming
                  || stagingRootState == .reclaimed else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A rejected outcome is paired with a committed build intent."
            )
          }
          return .rejected(rejection)
        case .outcomeUnknown:
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "An unknown commit outcome must not be persisted as terminal."
          )
        }
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func inspectCommitBase(
    _ submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    databaseID: DesignDatabaseID,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> (
    baseFacetRoots: [DesignFacetRoot],
    baseDependencyLock: DesignDependencyLock?,
    baseProjectionState: DesignProjectionRuntimeState?,
    rejectionReason: DesignCommitRejection.Reason?
  ) {
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction { transaction in
        guard let catalog = try await transaction.fetch(
          DesignDatabaseCatalogModel.self,
          identifiedBy: "catalog",
          consistency: .serializable
        ), catalog.databaseID == databaseID.description else {
          throw DesignDatabaseRuntimeError.databaseNotFound
        }
        let persistedSchemaDigest = try Self.contentDigest(
          algorithm: catalog.designSchemaBundleDigestAlgorithm,
          value: catalog.designSchemaBundleDigestValue
        )
        guard persistedSchemaDigest == submission.plan.designSchemaBundleDigest else {
          return (
            [],
            nil,
            nil,
            .schemaBundleMismatch(
              expected: persistedSchemaDigest,
              actual: submission.plan.designSchemaBundleDigest
            )
          )
        }
        guard let base = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: submission.plan.baseRevision.revisionID.description,
          consistency: .serializable
        ), base.databaseID == databaseID.description else {
          return (
            [],
            nil,
            nil,
            .baseRevisionNotFound(submission.plan.baseRevision)
          )
        }
        let baseLifecycle = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: submission.plan.baseRevision.revisionID.description,
          consistency: .serializable
        )
        try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
          baseLifecycle,
          revision: submission.plan.baseRevision,
          using: digester
        )
        let baseFacetRoots = try DesignDatabaseRuntimeFacetRootDirectory.decode(
          count: base.facetRootCount,
          encoded: base.facetRoots
        )
        let baseDependencyRootDigest = try Self.contentDigest(
          algorithm: base.dependencyRootDigestAlgorithm,
          value: base.dependencyRootDigestValue
        )
        let baseDependencyLock = try DesignDatabaseRuntimeDependencyLockDirectory
          .decode(
            count: base.dependencyLockEntryCount,
            encoded: base.dependencyLockEntries,
            expectedRootDigest: baseDependencyRootDigest,
            using: digester
          )
        guard baseDependencyRootDigest == submission.plan.dependencyRootDigest else {
          return (
            baseFacetRoots,
            baseDependencyLock,
            nil,
            .dependencyRootMismatch(
              expected: baseDependencyRootDigest,
              actual: submission.plan.dependencyRootDigest
            )
          )
        }
        let baseDependencyGraphDigest = try Self.contentDigest(
          algorithm: base.dependencyGraphDigestAlgorithm,
          value: base.dependencyGraphDigestValue
        )
        guard baseDependencyGraphDigest
          == submission.plan.semanticDependencyGraphDigest else {
          return (
            baseFacetRoots,
            baseDependencyLock,
            nil,
            .dependencyGraphMismatch(
              expected: baseDependencyGraphDigest,
              actual: submission.plan.semanticDependencyGraphDigest
            )
          )
        }
        if let candidate = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: candidateRevision.revisionID.description,
          consistency: .serializable
        ), candidate.databaseID == databaseID.description {
          return (
            baseFacetRoots,
            baseDependencyLock,
            nil,
            .candidateRevisionCollision(candidateRevision)
          )
        }
        let baseProjectionState = try await
          DesignDatabaseRuntimeProjectionDirectory.load(
            revision: submission.plan.baseRevision,
            databaseID: databaseID,
            count: base.projectionDescriptorCount,
            encoded: base.projectionDescriptorDigests,
            transaction: transaction,
            digester: digester
          )
        return (baseFacetRoots, baseDependencyLock, baseProjectionState, nil)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func recordCommitRejection(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    reason: DesignCommitRejection.Reason,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitResult {
    let rejection = try Self.commitRejection(
      operation: operation,
      submission: submission,
      reason: reason,
      using: digester
    )
    let model = try Self.commitOperationModel(rejection: rejection)
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let existingClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingOutcome = try await transaction.fetch(
          DesignCommitOperationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let existingIntent = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let identityReservation = try await transaction.fetch(
          DesignIdentityReservationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let validatedDirectory = try await transaction.fetch(
          DesignValidatedMutationDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let submissionCapsule = try await transaction.fetch(
          DesignCommitSubmissionModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        if let existingClaim {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            existingClaim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
              operation: key
            )
          }
          if let existingOutcome {
            return try Self.commitResult(
              model: existingOutcome,
              operation: operation,
              requestDigest: submission.requestDigest,
              using: digester
            )
          }
          guard identityReservation != nil, validatedDirectory != nil,
                let submissionCapsule else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "An active commit rejection has no atomic submission, validated input, and identity reservation."
            )
          }
          _ = try DesignDatabaseRuntimeCommitSubmissionCapsule(
            model: submissionCapsule,
            operation: operation,
            expectedRequestDigest: submission.requestDigest,
            expectedPlanDigest: submission.plan.planDigest,
            using: digester
          )
          guard let existingIntent else {
            try await transaction.save(model, precondition: .notExists)
            return .rejected(rejection)
          }
          let intentState = try DesignDatabaseRuntimeCommitBuildIntent.validateStored(
            existingIntent,
            operation: operation,
            submission: submission,
            candidateRevision: try Self.candidateRevision(
              operation: operation,
              requestDigest: submission.requestDigest
            ),
            using: digester
          )
          guard intentState == .staging || intentState == .prepared else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit build intent has no rejection outcome."
            )
          }
          let rejectedIntent = try DesignDatabaseRuntimeCommitBuildIntent
            .advanced(
              existingIntent,
              state: .rejected,
              using: digester
            )
          try await transaction.save(rejectedIntent, precondition: .exists)
          try await transaction.save(model, precondition: .notExists)
          return .rejected(rejection)
        }
        guard existingOutcome == nil, existingIntent == nil,
              identityReservation == nil, validatedDirectory == nil,
              submissionCapsule == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit rejection outcome or intent exists without its operation claim."
          )
        }
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(model, precondition: .notExists)
        return .rejected(rejection)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignCommitUnknown(
          operation: operation,
          requestDigest: submission.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  package static func maintenanceCommitRejection(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    reason: DesignCommitRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitRejection {
    try commitRejection(
      operation: operation,
      submission: submission,
      reason: reason,
      using: digester
    )
  }

  package static func maintenanceCommitOperationModel(
    rejection: DesignCommitRejection
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitOperationModel {
    try commitOperationModel(rejection: rejection)
  }

  package static func maintenanceCommitResult(
    model: DesignCommitOperationModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitResult {
    try commitResult(
      model: model,
      operation: operation,
      requestDigest: requestDigest,
      using: digester
    )
  }
}

private extension DesignDatabaseRuntimeAttachment {
  static func candidateRevision(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionReference {
    guard requestDigest.algorithm == .sha256,
          requestDigest.hexadecimalValue.utf8.count == 64 else {
      throw .commitTransactionFailed(
        reason: "A commit request digest must be SHA-256."
      )
    }
    let revisionHex = String(requestDigest.hexadecimalValue.prefix(32))
    do {
      return DesignRevisionReference(
        databaseID: operation.databaseID,
        revisionID: try DesignRevisionID(hexadecimalValue: revisionHex)
      )
    } catch {
      throw .commitTransactionFailed(
        reason: "The commit request digest could not form a revision identity."
      )
    }
  }

  static func aggregateChangeSetDigest(
    plan: DesignMutationPlan,
    prepared: [any DesignDatabaseRuntimePreparedMutation],
    projectionPlan: DesignDatabaseRuntimeCandidateProjectionPlan,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard projectionPlan.mutations.count == prepared.count else {
      throw .persistedStateCorrupt(
        reason: "The candidate projection plan does not cover every prepared mutation."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CandidateChangeSet"
    )
    encoder.append(plan.planDigest)
    encoder.append(UInt32(prepared.count))
    for (index, mutation) in prepared.enumerated() {
      let changes = projectionPlan.mutations[index]
      guard changes.segmentID == mutation.segmentID else {
        throw .persistedStateCorrupt(
          reason: "The candidate projection plan changed prepared mutation order."
        )
      }
      encoder.append(mutation.segmentID.rawValue)
      encoder.append(mutation.changeContributionDigest)
      try encoder.append(projectionChanges: changes.changes)
    }
    return try encoder.finalize(using: digester)
  }

  static func commitRejection(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    reason: DesignCommitRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitRejection {
    do {
      let outcomeDigest = try DesignMutationPlanDigest.rejectedOutcome(
        operation: operation,
        requestDigest: submission.requestDigest,
        planDigest: submission.plan.planDigest,
        reason: reason,
        using: digester
      )
      return DesignCommitRejection(
        operation: operation,
        requestDigest: submission.requestDigest,
        planDigest: submission.plan.planDigest,
        reason: reason,
        outcomeDigest: outcomeDigest
      )
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  static func revisionManifestModel(
    _ receipt: DesignCommitReceipt,
    directDependencyLock: DesignDependencyLock,
    projectionDescriptorCount: Int64,
    projectionDirectory: String
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionManifestModel {
    guard projectionDescriptorCount > 0 else {
      throw .persistedStateCorrupt(
        reason: "A candidate revision must publish at least one semantic projection."
      )
    }
    var model = DesignRevisionManifestModel()
    model.id = receipt.candidateRevision.revisionID.description
    model.databaseID = receipt.candidateRevision.databaseID.description
    model.parentCount = 1
    model.parentRevisionIDs = receipt.baseRevision.revisionID.description
    model.stateDigestAlgorithm = receipt.stateDigest.algorithm.rawValue
    model.stateDigestValue = receipt.stateDigest.hexadecimalValue
    model.schemaRootDigestAlgorithm = receipt.designSchemaBundleDigest.algorithm.rawValue
    model.schemaRootDigestValue = receipt.designSchemaBundleDigest.hexadecimalValue
    model.dependencyRootDigestAlgorithm = receipt.dependencyRootDigest.algorithm.rawValue
    model.dependencyRootDigestValue = receipt.dependencyRootDigest.hexadecimalValue
    model.dependencyLockEntryCount = Int64(directDependencyLock.entries.count)
    model.dependencyLockEntries = try DesignDatabaseRuntimeDependencyLockDirectory
      .encode(directDependencyLock)
    model.dependencyGraphDigestAlgorithm = receipt.semanticDependencyGraphDigest.algorithm.rawValue
    model.dependencyGraphDigestValue = receipt.semanticDependencyGraphDigest.hexadecimalValue
    model.facetRootCount = Int64(receipt.facetRoots.count)
    model.facetRoots = try DesignDatabaseRuntimeFacetRootDirectory.encode(
      receipt.facetRoots
    )
    model.projectionDescriptorCount = projectionDescriptorCount
    model.projectionDescriptorDigests = projectionDirectory
    model.directChangeRootDigestAlgorithm = receipt.changeSetDigest.algorithm.rawValue
    model.directChangeRootDigestValue = receipt.changeSetDigest.hexadecimalValue
    return model
  }

  static func commitOperationModel(
    receipt: DesignCommitReceipt
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitOperationModel {
    var model = baseCommitOperationModel(
      operation: receipt.operation,
      requestDigest: receipt.requestDigest,
      planDigest: receipt.planDigest
    )
    model.outcomeKind = 0
    model.baseRevisionID = receipt.baseRevision.revisionID.description
    model.candidateRevisionID = receipt.candidateRevision.revisionID.description
    model.stateDigestAlgorithm = receipt.stateDigest.algorithm.rawValue
    model.stateDigestValue = receipt.stateDigest.hexadecimalValue
    model.changeSetDigestAlgorithm = receipt.changeSetDigest.algorithm.rawValue
    model.changeSetDigestValue = receipt.changeSetDigest.hexadecimalValue
    model.schemaBundleDigestAlgorithm = receipt.designSchemaBundleDigest.algorithm.rawValue
    model.schemaBundleDigestValue = receipt.designSchemaBundleDigest.hexadecimalValue
    model.dependencyRootDigestAlgorithm = receipt.dependencyRootDigest.algorithm.rawValue
    model.dependencyRootDigestValue = receipt.dependencyRootDigest.hexadecimalValue
    model.dependencyGraphDigestAlgorithm = receipt.semanticDependencyGraphDigest.algorithm.rawValue
    model.dependencyGraphDigestValue = receipt.semanticDependencyGraphDigest.hexadecimalValue
    model.facetRootCount = Int64(receipt.facetRoots.count)
    model.facetRoots = try DesignDatabaseRuntimeFacetRootDirectory.encode(
      receipt.facetRoots
    )
    model.outcomeDigestAlgorithm = receipt.outcomeDigest.algorithm.rawValue
    model.outcomeDigestValue = receipt.outcomeDigest.hexadecimalValue
    return model
  }

  static func commitOperationModel(
    rejection: DesignCommitRejection
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitOperationModel {
    var model = baseCommitOperationModel(
      operation: rejection.operation,
      requestDigest: rejection.requestDigest,
      planDigest: rejection.planDigest
    )
    model.outcomeKind = 1
    switch rejection.reason {
    case .baseRevisionNotFound(let revision):
      model.rejectionKind = 0
      model.rejectionRevisionID = revision.revisionID.description
    case .schemaBundleMismatch(let expected, let actual):
      model.rejectionKind = 1
      model.rejectionExpectedDigestAlgorithm = expected.algorithm.rawValue
      model.rejectionExpectedDigestValue = expected.hexadecimalValue
      model.rejectionActualDigestAlgorithm = actual.algorithm.rawValue
      model.rejectionActualDigestValue = actual.hexadecimalValue
    case .dependencyRootMismatch(let expected, let actual):
      model.rejectionKind = 7
      model.rejectionExpectedDigestAlgorithm = expected.algorithm.rawValue
      model.rejectionExpectedDigestValue = expected.hexadecimalValue
      model.rejectionActualDigestAlgorithm = actual.algorithm.rawValue
      model.rejectionActualDigestValue = actual.hexadecimalValue
    case .dependencyGraphMismatch(let expected, let actual):
      model.rejectionKind = 8
      model.rejectionExpectedDigestAlgorithm = expected.algorithm.rawValue
      model.rejectionExpectedDigestValue = expected.hexadecimalValue
      model.rejectionActualDigestAlgorithm = actual.algorithm.rawValue
      model.rejectionActualDigestValue = actual.hexadecimalValue
    case .adapterUnavailable(let schemaID, let adapterVersion):
      model.rejectionKind = 2
      model.rejectionSchemaID = schemaID.rawValue
      model.rejectionAdapterVersion = adapterVersion
    case .invalidSegmentPayload(let segmentID, let detail):
      model.rejectionKind = 3
      model.rejectionSegmentID = segmentID.rawValue
      model.rejectionDetail = detail
    case .validationFailed(let diagnostics, let diagnosticsDigest):
      model.rejectionKind = 4
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        model.rejectionDiagnosticsJSON = String(
          decoding: try encoder.encode(diagnostics),
          as: UTF8.self
        )
      } catch {
        throw .commitTransactionFailed(
          reason: "Commit diagnostics could not be encoded: \(error)"
        )
      }
      model.rejectionDiagnosticsDigestAlgorithm = diagnosticsDigest.algorithm.rawValue
      model.rejectionDiagnosticsDigestValue = diagnosticsDigest.hexadecimalValue
    case .budgetExceeded(let limit, let requested):
      model.rejectionKind = 5
      model.rejectionLimit = String(limit)
      model.rejectionRequested = String(requested)
    case .candidateRevisionCollision(let revision):
      model.rejectionKind = 6
      model.rejectionRevisionID = revision.revisionID.description
    case .abandonedByMaintenance(
      let operation,
      let requestDigest,
      let reason,
      let evidenceDigest
    ):
      model.rejectionKind = 9
      model.rejectionMaintenanceSubjectScopeID =
        operation.authorizationSubjectScopeID.description
      model.rejectionMaintenanceOperationID = operation.operationID.rawValue
      model.rejectionMaintenanceRequestDigestAlgorithm =
        requestDigest.algorithm.rawValue
      model.rejectionMaintenanceRequestDigestValue =
        requestDigest.hexadecimalValue
      model.rejectionMaintenanceReason = reason.rawValue
      model.rejectionMaintenanceEvidenceDigestAlgorithm =
        evidenceDigest.algorithm.rawValue
      model.rejectionMaintenanceEvidenceDigestValue =
        evidenceDigest.hexadecimalValue
    }
    model.outcomeDigestAlgorithm = rejection.outcomeDigest.algorithm.rawValue
    model.outcomeDigestValue = rejection.outcomeDigest.hexadecimalValue
    return model
  }

  static func baseCommitOperationModel(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest
  ) -> DesignCommitOperationModel {
    var model = DesignCommitOperationModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    model.planDigestAlgorithm = planDigest.algorithm.rawValue
    model.planDigestValue = planDigest.hexadecimalValue
    return model
  }

  static func commitResult(
    model: DesignCommitOperationModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitResult {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A commit operation does not match its persisted scope."
      )
    }
    let planDigest = try contentDigest(
      algorithm: model.planDigestAlgorithm,
      value: model.planDigestValue
    )
    let outcomeDigest = try contentDigest(
      algorithm: model.outcomeDigestAlgorithm,
      value: model.outcomeDigestValue
    )
    switch model.outcomeKind {
    case 0:
      let base = try revision(
        databaseID: operation.databaseID,
        revisionID: model.baseRevisionID
      )
      let candidate = try revision(
        databaseID: operation.databaseID,
        revisionID: model.candidateRevisionID
      )
      let stateDigest = try contentDigest(
        algorithm: model.stateDigestAlgorithm,
        value: model.stateDigestValue
      )
      let changeSetDigest = try contentDigest(
        algorithm: model.changeSetDigestAlgorithm,
        value: model.changeSetDigestValue
      )
      let schemaDigest = try contentDigest(
        algorithm: model.schemaBundleDigestAlgorithm,
        value: model.schemaBundleDigestValue
      )
      let dependencyRootDigest = try contentDigest(
        algorithm: model.dependencyRootDigestAlgorithm,
        value: model.dependencyRootDigestValue
      )
      let dependencyGraphDigest = try contentDigest(
        algorithm: model.dependencyGraphDigestAlgorithm,
        value: model.dependencyGraphDigestValue
      )
      let facetRoots = try DesignDatabaseRuntimeFacetRootDirectory.decode(
        count: model.facetRootCount,
        encoded: model.facetRoots
      )
      let expectedOutcome: ContentDigest
      do {
        expectedOutcome = try DesignMutationPlanDigest.committedOutcome(
          operation: operation,
          requestDigest: requestDigest,
          planDigest: planDigest,
          baseRevision: base,
          candidateRevision: candidate,
          stateDigest: stateDigest,
          changeSetDigest: changeSetDigest,
          designSchemaBundleDigest: schemaDigest,
          dependencyRootDigest: dependencyRootDigest,
          semanticDependencyGraphDigest: dependencyGraphDigest,
          facetRoots: facetRoots,
          using: digester
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A committed outcome digest could not be reconstructed."
        )
      }
      guard outcomeDigest == expectedOutcome else {
        throw .persistedStateCorrupt(
          reason: "A committed outcome digest does not match its payload."
        )
      }
      return .committed(
        DesignCommitReceipt(
          operation: operation,
          requestDigest: requestDigest,
          planDigest: planDigest,
          baseRevision: base,
          candidateRevision: candidate,
          stateDigest: stateDigest,
          changeSetDigest: changeSetDigest,
          designSchemaBundleDigest: schemaDigest,
          dependencyRootDigest: dependencyRootDigest,
          semanticDependencyGraphDigest: dependencyGraphDigest,
          facetRoots: facetRoots,
          outcomeDigest: outcomeDigest
        )
      )
    case 1:
      let reason = try rejectionReason(model, databaseID: operation.databaseID)
      let expectedOutcome: ContentDigest
      do {
        expectedOutcome = try DesignMutationPlanDigest.rejectedOutcome(
          operation: operation,
          requestDigest: requestDigest,
          planDigest: planDigest,
          reason: reason,
          using: digester
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A rejected outcome digest could not be reconstructed."
        )
      }
      guard outcomeDigest == expectedOutcome else {
        throw .persistedStateCorrupt(
          reason: "A rejected outcome digest does not match its payload."
        )
      }
      return .rejected(
        DesignCommitRejection(
          operation: operation,
          requestDigest: requestDigest,
          planDigest: planDigest,
          reason: reason,
          outcomeDigest: outcomeDigest
        )
      )
    default:
      throw .persistedStateCorrupt(
        reason: "A commit operation contains an unknown outcome kind."
      )
    }
  }

  static func rejectionReason(
    _ model: DesignCommitOperationModel,
    databaseID: DesignDatabaseID
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitRejection.Reason {
    switch model.rejectionKind {
    case 0:
      return .baseRevisionNotFound(
        try revision(databaseID: databaseID, revisionID: model.rejectionRevisionID)
      )
    case 1:
      return .schemaBundleMismatch(
        expected: try contentDigest(
          algorithm: model.rejectionExpectedDigestAlgorithm,
          value: model.rejectionExpectedDigestValue
        ),
        actual: try contentDigest(
          algorithm: model.rejectionActualDigestAlgorithm,
          value: model.rejectionActualDigestValue
        )
      )
    case 2:
      do {
        return .adapterUnavailable(
          schemaID: try DesignSchemaID(rawValue: model.rejectionSchemaID),
          adapterVersion: model.rejectionAdapterVersion
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A commit rejection contains a malformed adapter binding."
        )
      }
    case 3:
      do {
        return .invalidSegmentPayload(
          segmentID: try DesignMutationPlanSegmentID(
            rawValue: model.rejectionSegmentID
          ),
          reason: model.rejectionDetail
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A commit rejection contains a malformed segment binding."
        )
      }
    case 4:
      do {
        let diagnostics = try JSONDecoder().decode(
          [DesignDiagnostic].self,
          from: Data(model.rejectionDiagnosticsJSON.utf8)
        )
        return .validationFailed(
          diagnostics: diagnostics,
          diagnosticsDigest: try contentDigest(
            algorithm: model.rejectionDiagnosticsDigestAlgorithm,
            value: model.rejectionDiagnosticsDigestValue
          )
        )
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .persistedStateCorrupt(
          reason: "Commit rejection diagnostics are malformed: \(error)"
        )
      }
    case 5:
      guard let limit = UInt64(model.rejectionLimit),
            let requested = UInt64(model.rejectionRequested) else {
        throw .persistedStateCorrupt(
          reason: "A commit rejection contains malformed budget values."
        )
      }
      return .budgetExceeded(limit: limit, requested: requested)
    case 6:
      return .candidateRevisionCollision(
        try revision(databaseID: databaseID, revisionID: model.rejectionRevisionID)
      )
    case 7:
      return .dependencyRootMismatch(
        expected: try contentDigest(
          algorithm: model.rejectionExpectedDigestAlgorithm,
          value: model.rejectionExpectedDigestValue
        ),
        actual: try contentDigest(
          algorithm: model.rejectionActualDigestAlgorithm,
          value: model.rejectionActualDigestValue
        )
      )
    case 8:
      return .dependencyGraphMismatch(
        expected: try contentDigest(
          algorithm: model.rejectionExpectedDigestAlgorithm,
          value: model.rejectionExpectedDigestValue
        ),
        actual: try contentDigest(
          algorithm: model.rejectionActualDigestAlgorithm,
          value: model.rejectionActualDigestValue
        )
      )
    case 9:
      do {
        return .abandonedByMaintenance(
          operation: DesignDatabaseOperationReference(
            databaseID: databaseID,
            authorizationSubjectScopeID:
              try DesignAuthorizationSubjectScopeID(
                hexadecimalValue: model.rejectionMaintenanceSubjectScopeID
              ),
            operationID: try DesignDatabaseOperationID(
              rawValue: model.rejectionMaintenanceOperationID
            )
          ),
          requestDigest: try contentDigest(
            algorithm: model.rejectionMaintenanceRequestDigestAlgorithm,
            value: model.rejectionMaintenanceRequestDigestValue
          ),
          reason: try DesignCommitAbandonmentReason(
            rawValue: model.rejectionMaintenanceReason
          ),
          evidenceDigest: try contentDigest(
            algorithm: model.rejectionMaintenanceEvidenceDigestAlgorithm,
            value: model.rejectionMaintenanceEvidenceDigestValue
          )
        )
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .persistedStateCorrupt(
          reason: "A commit rejection contains a malformed maintenance binding."
        )
      }
    default:
      throw .persistedStateCorrupt(
        reason: "A commit operation contains an unknown rejection kind."
      )
    }
  }

  static func revision(
    databaseID: DesignDatabaseID,
    revisionID: String
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionReference {
    do {
      return DesignRevisionReference(
        databaseID: databaseID,
        revisionID: try DesignRevisionID(hexadecimalValue: revisionID)
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit operation contains a malformed revision identity."
      )
    }
  }

  static func contentDigest(
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
        reason: "A commit operation contains a malformed content digest."
      )
    }
  }
}
