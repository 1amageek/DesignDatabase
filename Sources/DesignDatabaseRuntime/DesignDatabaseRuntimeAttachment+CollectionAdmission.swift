import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func admitRevisionCollection(
    _ request: DesignDatabaseRuntimeCollectionAdmissionRequest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionAdmissionResult
  {
    try await admitRevisionCollection(
      request,
      budget: DesignDatabaseRuntimeCollectionRootAuditBudget(),
      digester: digester
    )
  }

  package func admitRevisionCollection(
    _ request: DesignDatabaseRuntimeCollectionAdmissionRequest,
    budget: DesignDatabaseRuntimeCollectionRootAuditBudget,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionAdmissionResult
  {
    guard request.operation.databaseID == request.candidates.databaseID else {
      throw .persistedStateCorrupt(
        reason: "A collection admission request crosses a database boundary."
      )
    }
    if let existing = try await existingCollectionAdmission(
      request,
      maximumPhysicalIdentityCount: budget.maximumPhysicalClaimCount,
      using: digester
    ) {
      return existing
    }
    let databaseContext = try context()
    var admissionAttempt: UInt64 = 0
    var lastExpectedReachabilityGeneration: Int64 = 0
    var lastActualReachabilityGeneration: Int64 = 0
    while admissionAttempt < budget.maximumGenerationRetryCount {
      admissionAttempt += 1
      let rootAudit = try await DesignDatabaseRuntimeCollectionRootAuditor(
        context: databaseContext,
        databaseID: request.operation.databaseID,
        candidates: request.candidates,
        budget: budget,
        digester: digester
      ).audit()
      let physicalRootAudit = try await
        DesignDatabaseRuntimeCollectionPhysicalRootAuditor(
          context: databaseContext,
          databaseID: request.operation.databaseID,
          candidates: request.candidates,
          budget: budget,
          digester: digester
        ).audit()
      guard rootAudit.observedReachabilityGeneration
              == physicalRootAudit.observedReachabilityGeneration else {
        lastExpectedReachabilityGeneration = rootAudit
          .observedReachabilityGeneration
        lastActualReachabilityGeneration = physicalRootAudit
          .observedReachabilityGeneration
        continue
      }
      let physicalIdentityDirectory = try
        DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
          identities: physicalRootAudit.claimedIdentities,
          rejectedStagingRootIDs: physicalRootAudit.rejectedStagingRootIDs,
          maximumIdentityCount: budget.maximumPhysicalClaimCount,
          using: digester
        )
      guard physicalIdentityDirectory.identitySetDigest
              == physicalRootAudit.claimSetDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A physical root audit changed while forming its claim directory."
        )
      }
      try requirePhysicalWriteReclaimers(
        for: physicalRootAudit.claimedIdentities
      )
      try Self.requireCollectionAdmissionTransactionBudget(
        physicalIdentityCount: physicalIdentityDirectory.identities.count,
        revisionCount: request.candidates.revisions.count,
        rejectedStagingRootCount: physicalIdentityDirectory
          .rejectedStagingRootIDs.count
      )
      var physicalClaims: [DesignPhysicalCollectionClaimModel] = []
      physicalClaims.reserveCapacity(
        physicalRootAudit.claimedIdentities.count
      )
      for identity in physicalRootAudit.claimedIdentities {
        physicalClaims.append(
          try DesignDatabaseRuntimePhysicalCollectionClaim.makeClaimed(
          identity: identity,
          collectionIntentID: DesignDatabaseRuntimeOperationClaim.key(
            request.operation
          ),
          using: digester
        )
        )
      }
      let persistedPhysicalClaims = physicalClaims
      let token = try await snapshotLeaseCoordinator.admitDeletion(
        identifier: DesignDatabaseRuntimeOperationClaim.key(request.operation),
        candidates: request.candidates
      )
      let leaseObservation: DesignDatabaseRuntimeLeaseObservation
      do {
        leaseObservation = try await snapshotLeaseCoordinator.observation()
      } catch let error {
        try await snapshotLeaseCoordinator.releaseDeletionAdmission(token)
        throw error
      }
      do {
        let intent = try await databaseContext.withTransaction(
          configuration: .batch
        ) { transaction in
          let key = DesignDatabaseRuntimeOperationClaim.key(request.operation)
          let existingClaim = try await transaction.fetch(
            DesignOperationClaimModel.self,
            identifiedBy: key,
            consistency: .serializable
          )
          let existingIntent = try await transaction.fetch(
            DesignCollectionIntentModel.self,
            identifiedBy: key,
            consistency: .serializable
          )
          let existingPhysicalDirectory = try await transaction.fetch(
            DesignCollectionPhysicalIdentityDirectoryModel.self,
            identifiedBy: key,
            consistency: .serializable
          )
          guard existingClaim == nil, existingIntent == nil,
                existingPhysicalDirectory == nil else {
            throw DesignDatabaseRuntimeError.collectionIdempotencyConflict(
              operation: key
            )
          }
          let reachability = try await DesignDatabaseRuntimeReachability.require(
            databaseID: request.operation.databaseID,
            transaction: transaction
          )
          guard reachability.generation
              == rootAudit.observedReachabilityGeneration,
            reachability.generation
              == physicalRootAudit.observedReachabilityGeneration else {
            throw DesignDatabaseRuntimeError.collectionReachabilityChanged(
              expected: rootAudit.observedReachabilityGeneration,
              actual: reachability.generation
            )
          }
          var reusablePhysicalClaimIDs = Set<String>()
          for (identity, physicalClaim) in zip(
            physicalRootAudit.claimedIdentities,
            persistedPhysicalClaims
          ) {
            if let existingPhysicalClaim = try await transaction.fetch(
              DesignPhysicalCollectionClaimModel.self,
              identifiedBy: physicalClaim.id,
              consistency: .serializable
            ) {
              let state = try DesignDatabaseRuntimePhysicalCollectionClaim.validate(
                existingPhysicalClaim,
                expectedIdentity: identity,
                using: digester
              )
              switch state {
              case .claimed:
                throw DesignDatabaseRuntimeError.physicalWriteDeleting(
                  identity: existingPhysicalClaim.id,
                  collectionOperation: existingPhysicalClaim.collectionIntentID
                )
              case .deleted:
                reusablePhysicalClaimIDs.insert(existingPhysicalClaim.id)
              }
            }
          }
          let revisionIDs = request.candidates.revisions.map(
            \.revisionID.description
          )
          let manifests = try await transaction.fetch(
            DesignRevisionManifestModel.self,
            identifiedBy: revisionIDs,
            consistency: .serializable
          )
          let lifecycles = try await transaction.fetch(
            DesignRevisionLifecycleModel.self,
            identifiedBy: revisionIDs,
            consistency: .serializable
          )
          guard manifests.count == revisionIDs.count,
                lifecycles.count == revisionIDs.count else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A collection candidate disappeared after root audit."
            )
          }
          let updatedReachability = try DesignDatabaseRuntimeReachability
            .advanced(reachability, kind: "reachability")
          let rejectedRootIDs = physicalIdentityDirectory
            .rejectedStagingRootIDs
          let rejectedRoots: [DesignStagingRootModel]
          let rejectedIntents: [DesignCommitBuildIntentModel]
          if rejectedRootIDs.isEmpty {
            rejectedRoots = []
            rejectedIntents = []
          } else {
            rejectedRoots = try await transaction.fetch(
              DesignStagingRootModel.self,
              identifiedBy: rejectedRootIDs,
              consistency: .serializable
            )
            rejectedIntents = try await transaction.fetch(
              DesignCommitBuildIntentModel.self,
              identifiedBy: rejectedRootIDs,
              consistency: .serializable
            )
          }
          guard rejectedRoots.count == rejectedRootIDs.count,
                rejectedIntents.count == rejectedRootIDs.count else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A rejected staging root disappeared after root audit."
            )
          }
          var reclaimingRoots: [DesignStagingRootModel] = []
          reclaimingRoots.reserveCapacity(rejectedRootIDs.count)
          for rootID in rejectedRootIDs {
            guard let root = rejectedRoots.first(where: { $0.id == rootID }),
                  let buildIntent = rejectedIntents.first(where: {
                    $0.id == rootID
                  }) else {
              throw DesignDatabaseRuntimeError.persistedStateCorrupt(
                reason: "A rejected staging root binding is incomplete."
              )
            }
            _ = try DesignDatabaseRuntimeRejectedStagingRoot.validate(
              root,
              intent: buildIntent,
              databaseID: request.operation.databaseID,
              expectedState: .rejected,
              using: digester
            )
            reclaimingRoots.append(
              try DesignDatabaseRuntimeStagingRoot.beganReclamation(
                root,
                reachabilityGeneration: updatedReachability.generation,
                using: digester
              )
            )
          }
          var deletingLifecycles: [DesignRevisionLifecycleModel] = []
          deletingLifecycles.reserveCapacity(revisionIDs.count)
          for revision in request.candidates.revisions {
            guard manifests.contains(where: {
              $0.id == revision.revisionID.description
                && $0.databaseID == request.operation.databaseID.description
            }), let lifecycle = lifecycles.first(where: {
              $0.revisionID == revision.revisionID.description
            }) else {
              throw DesignDatabaseRuntimeError.persistedStateCorrupt(
                reason: "A collection candidate has an inconsistent manifest or lifecycle."
              )
            }
            deletingLifecycles.append(
              try DesignDatabaseRuntimeRevisionLifecycle.transitioned(
                lifecycle,
                revision: revision,
                from: .visible,
                to: .deleting,
                reachabilityGeneration: updatedReachability.generation,
                using: digester
              )
            )
          }
          let intent = try DesignDatabaseRuntimeCollectionIntent.makeAdmitted(
            operation: request.operation,
            requestDigest: request.requestDigest,
            candidates: request.candidates,
            originalRootSetDigest: rootAudit.rootSetDigest,
            physicalRootSetDigest: physicalRootAudit.rootSetDigest,
            physicalIdentityDirectoryDigest: physicalIdentityDirectory.digest,
            physicalIdentityCount: UInt64(
              physicalIdentityDirectory.identities.count
            ),
            observedReachabilityGeneration: rootAudit
              .observedReachabilityGeneration,
            admittedReachabilityGeneration: updatedReachability.generation,
            leaseObservationGeneration: leaseObservation.generation,
            using: digester
          )
          try await transaction.save(
            DesignDatabaseRuntimeOperationClaim.make(
              operation: request.operation,
              kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
              requestDigest: request.requestDigest
            ),
            precondition: .notExists
          )
          try await transaction.save(intent, precondition: .notExists)
          try await transaction.save(
            physicalIdentityDirectory.model(
              operation: request.operation,
              requestDigest: request.requestDigest
            ),
            precondition: .notExists
          )
          for physicalClaim in persistedPhysicalClaims {
            try await transaction.save(
              physicalClaim,
              precondition: reusablePhysicalClaimIDs.contains(physicalClaim.id)
                ? .exists
                : .notExists
            )
          }
          for lifecycle in deletingLifecycles {
            try await transaction.save(lifecycle, precondition: .exists)
          }
          for root in reclaimingRoots {
            try await transaction.save(root, precondition: .exists)
          }
          try await transaction.save(
            updatedReachability,
            precondition: .exists
          )
          return intent
        }
        return .admitted(intent)
      } catch DatabaseContextError.commitOutcomeUnknown {
        if let reconciled = try await existingCollectionAdmission(
          request,
          maximumPhysicalIdentityCount: budget.maximumPhysicalClaimCount,
          using: digester
        ) {
          return reconciled
        }
        return .outcomeUnknown(
          operation: request.operation,
          requestDigest: request.requestDigest
        )
      } catch let error as DesignDatabaseRuntimeError {
        if let reconciled = try await existingCollectionAdmission(
          request,
          maximumPhysicalIdentityCount: budget.maximumPhysicalClaimCount,
          using: digester
        ) {
          return reconciled
        }
        try await snapshotLeaseCoordinator.releaseDeletionAdmission(token)
        if case .collectionReachabilityChanged(
          let expected,
          let actual
        ) = error {
          lastExpectedReachabilityGeneration = expected
          lastActualReachabilityGeneration = actual
          continue
        }
        throw error
      } catch {
        try await snapshotLeaseCoordinator.releaseDeletionAdmission(token)
        throw .commitTransactionFailed(reason: String(describing: error))
      }
    }
    throw .collectionReachabilityChanged(
      expected: lastExpectedReachabilityGeneration,
      actual: lastActualReachabilityGeneration
    )
  }

  private func existingCollectionAdmission(
    _ request: DesignDatabaseRuntimeCollectionAdmissionRequest,
    maximumPhysicalIdentityCount: UInt64,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionAdmissionResult?
  {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(request.operation)
    guard let maximumRevisionCount = UInt64(
      exactly: request.candidates.revisions.count
    ) else {
      throw .deletionCandidateBudgetExceeded(
        limit: UInt64.max,
        requested: UInt64.max
      )
    }
    let persisted: (
      DesignOperationClaimModel?,
      DesignCollectionIntentModel?,
      DesignCollectionPhysicalIdentityDirectoryModel?
    )
    do {
      persisted = try await databaseContext.withTransaction { transaction in
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let intent = try await transaction.fetch(
          DesignCollectionIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let physicalIdentityDirectory = try await transaction.fetch(
          DesignCollectionPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        return (claim, intent, physicalIdentityDirectory)
      }
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    switch persisted {
    case (nil, nil, nil):
      return nil
    case (let claim?, let intent?, let physicalIdentityDirectoryModel?):
      guard try DesignDatabaseRuntimeOperationClaim.matches(
        claim,
        operation: request.operation,
        kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
        requestDigest: request.requestDigest
      ) else {
        throw .collectionIdempotencyConflict(operation: key)
      }
      let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
        intent,
        maximumRevisionCount: maximumRevisionCount,
        using: digester
      )
      guard recovered.operation == request.operation,
            recovered.requestDigest == request.requestDigest,
            recovered.candidates == request.candidates else {
        throw .collectionIdempotencyConflict(operation: key)
      }
      let physicalIdentityDirectory = try
        DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
          model: physicalIdentityDirectoryModel,
          operation: request.operation,
          requestDigest: request.requestDigest,
          maximumIdentityCount: maximumPhysicalIdentityCount,
          using: digester
        )
      guard recovered.physicalIdentityDirectoryDigest
              == physicalIdentityDirectory.digest,
            recovered.physicalIdentityCount
              == UInt64(physicalIdentityDirectory.identities.count) else {
        throw .persistedStateCorrupt(
          reason: "A collection intent does not bind its physical identity directory."
        )
      }
      try await validateRejectedStagingRootStates(
        directory: physicalIdentityDirectory,
        collectionState: recovered.state,
        databaseID: recovered.operation.databaseID,
        context: databaseContext,
        using: digester
      )
      if recovered.state != .collected {
        _ = try await DesignDatabaseRuntimeCollectionPhysicalClaimValidator
          .validate(
          directory: physicalIdentityDirectory,
          collectionIntentID: key,
          context: databaseContext,
          using: digester
        )
      }
      try await restoreCollectionAdmission(
        intent,
        maximumRevisionCount: maximumRevisionCount,
        using: digester
      )
      switch recovered.state {
      case .admitted, .sweeping:
        return .admitted(intent)
      case .collected:
        return .collected(intent)
      }
    default:
      throw .persistedStateCorrupt(
        reason: "A collection operation claim and intent are not atomic."
      )
    }
  }

  private nonisolated func requirePhysicalWriteReclaimers(
    for identities: [DesignDatabaseRuntimeImmutableWriteIdentity]
  ) throws(DesignDatabaseRuntimeError) {
    for identity in identities where
      !DesignDatabaseRuntimePhysicalCollectionClaim
        .isRuntimeManagedStorageType(identity.storageType)
        && physicalWriteReclaimers[identity.storageType] == nil
    {
      throw .physicalWriteReclaimerUnavailable(
        storageType: identity.storageType
      )
    }
  }

  private static func requireCollectionAdmissionTransactionBudget(
    physicalIdentityCount: Int,
    revisionCount: Int,
    rejectedStagingRootCount: Int
  ) throws(DesignDatabaseRuntimeError) {
    guard let physicalCount = UInt64(exactly: physicalIdentityCount),
          let lifecycleCount = UInt64(exactly: revisionCount),
          let stagingRootCount = UInt64(
            exactly: rejectedStagingRootCount
          ) else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "collection admission transaction writes",
        limit: DesignDatabaseRuntimeCommitBuildIntent.stagingTransactionWriteLimit,
        requested: UInt64.max
      )
    }
    let (physicalAndLifecycleCount, firstOverflow) = physicalCount
      .addingReportingOverflow(lifecycleCount)
    let (variableWriteCount, secondOverflow) = physicalAndLifecycleCount
      .addingReportingOverflow(stagingRootCount)
    let (writeCount, thirdOverflow) = variableWriteCount
      .addingReportingOverflow(4)
    guard !firstOverflow,
          !secondOverflow,
          !thirdOverflow,
          writeCount <= DesignDatabaseRuntimeCommitBuildIntent
            .stagingTransactionWriteLimit else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "collection admission transaction writes",
        limit: DesignDatabaseRuntimeCommitBuildIntent.stagingTransactionWriteLimit,
        requested: firstOverflow || secondOverflow || thirdOverflow
          ? UInt64.max
          : writeCount
      )
    }
  }

}
