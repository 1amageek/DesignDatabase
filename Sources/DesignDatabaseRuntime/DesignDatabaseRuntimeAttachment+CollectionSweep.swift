import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

private struct DesignDatabaseRuntimeLoadedCollectionSweep: Sendable {
  let intent: DesignCollectionIntentModel
  let operation: DesignDatabaseOperationReference
  let requestDigest: ContentDigest
  let candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  let originalRootSetDigest: ContentDigest
  let physicalRootSetDigest: ContentDigest
  let physicalIdentityDirectoryDigest: ContentDigest
  let directory: DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory
  let state: DesignDatabaseRuntimeCollectionIntent.State
}

extension DesignDatabaseRuntimeAttachment {
  /// Global maintenance reconciliation validates persisted state without advancing deletion.
  package func revisionCollectionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    maximumRevisionCount: UInt64,
    maximumPhysicalIdentityCount: UInt64,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeCollectionSweepResult? {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    let absent: Bool
    do {
      absent = try await databaseContext.withTransaction { transaction in
        let claim = try await transaction.fetch(DesignOperationClaimModel.self, identifiedBy: key, consistency: .serializable)
        let intent = try await transaction.fetch(DesignCollectionIntentModel.self, identifiedBy: key, consistency: .serializable)
        let directory = try await transaction.fetch(DesignCollectionPhysicalIdentityDirectoryModel.self, identifiedBy: key, consistency: .serializable)
        return claim == nil && intent == nil && directory == nil
      }
    } catch { throw .commitTransactionFailed(reason: String(describing: error)) }
    if absent { return nil }
    let loaded = try await loadCollectionSweep(operation: operation, requestDigest: requestDigest,
      maximumRevisionCount: maximumRevisionCount, maximumPhysicalIdentityCount: maximumPhysicalIdentityCount,
      using: digester)
    return try collectionSweepResult(loaded)
  }

  package func sweepRevisionCollection(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    maximumPhysicalDeletionCount: UInt64 = 16,
    maximumRevisionCount: UInt64 = 256,
    maximumPhysicalIdentityCount: UInt64 = 256,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionSweepResult
  {
    let maximumBatchDeletionCount = (
      DesignDatabaseRuntimeCommitBuildIntent.stagingTransactionWriteLimit - 1
    ) / 2
    guard maximumPhysicalDeletionCount > 0,
          maximumPhysicalDeletionCount <= maximumBatchDeletionCount else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "collection sweep physical deletions",
        limit: maximumBatchDeletionCount,
        requested: maximumPhysicalDeletionCount
      )
    }
    let initial = try await loadCollectionSweep(
      operation: operation,
      requestDigest: requestDigest,
      maximumRevisionCount: maximumRevisionCount,
      maximumPhysicalIdentityCount: maximumPhysicalIdentityCount,
      using: digester
    )
    if initial.state == .collected {
      let result = try collectionSweepResult(initial)
      try await releaseCollectionAdmission(initial)
      return result
    }
    let initialDeletedCount = initial.intent.deletedPhysicalIdentityCount
    let databaseContext = try context()
    do {
      let updatedIntent = try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let key = DesignDatabaseRuntimeOperationClaim.key(operation)
        guard let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        ), let intent = try await transaction.fetch(
          DesignCollectionIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        ), let directoryModel = try await transaction.fetch(
          DesignCollectionPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        ), try DesignDatabaseRuntimeOperationClaim.matches(
          claim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A collection sweep is missing its atomic operation state."
          )
        }
        let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
          intent,
          maximumRevisionCount: maximumRevisionCount,
          using: digester
        )
        guard recovered.operation == operation,
              recovered.requestDigest == requestDigest,
              recovered.state != .collected else {
          throw DesignDatabaseRuntimeError.collectionIdempotencyConflict(
            operation: key
          )
        }
        let directory = try
          DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
            model: directoryModel,
            operation: operation,
            requestDigest: requestDigest,
            maximumIdentityCount: maximumPhysicalIdentityCount,
            using: digester
          )
        guard recovered.physicalIdentityDirectoryDigest == directory.digest,
              recovered.physicalIdentityCount
                == UInt64(directory.identities.count),
              let startIndex = Int(
                exactly: intent.deletedPhysicalIdentityCount
              ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A collection sweep intent does not bind its physical directory progress."
          )
        }
        let batch = try Self.collectionSweepBatch(
          startIndex: startIndex,
          physicalIdentityCount: directory.identities.count,
          revisionCount: recovered.candidates.revisions.count,
          rejectedStagingRootCount: directory.rejectedStagingRootIDs.count,
          maximumPhysicalDeletionCount: maximumPhysicalDeletionCount
        )
        for index in batch.range {
          let identity = directory.identities[index]
          let claimKey = try DesignDatabaseRuntimePhysicalCollectionClaim.key(
            for: identity,
            using: digester
          )
          guard let physicalClaim = try await transaction.fetch(
            DesignPhysicalCollectionClaimModel.self,
            identifiedBy: claimKey,
            consistency: .serializable
          ), physicalClaim.collectionIntentID == key else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A collection sweep physical claim is missing or has another owner."
            )
          }
          guard try DesignDatabaseRuntimePhysicalCollectionClaim.validate(
            physicalClaim,
            expectedIdentity: identity,
            using: digester
          ) == .claimed else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A collection sweep encountered a non-claimed physical identity."
            )
          }
          try await self.deletePhysicalWrite(identity, from: transaction)
          try await transaction.save(
            try DesignDatabaseRuntimePhysicalCollectionClaim
              .transitionedDeleted(
                physicalClaim,
                expectedIdentity: identity,
                collectionIntentID: key,
                using: digester
              ),
            precondition: .exists
          )
        }
        let deletedCount = UInt64(batch.range.upperBound)
        if batch.isTerminal {
          let reachability = try await DesignDatabaseRuntimeReachability.require(
            databaseID: operation.databaseID,
            transaction: transaction
          )
          guard reachability.generation
                  >= intent.admittedReachabilityGeneration else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A collection sweep completion precedes its admission generation."
            )
          }
          let completedReachability = try DesignDatabaseRuntimeReachability
            .advanced(reachability, kind: "collection completion")
          let rejectedRootIDs = directory.rejectedStagingRootIDs
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
              reason: "A collection completion is missing a rejected staging root."
            )
          }
          var reclaimedRoots: [DesignStagingRootModel] = []
          reclaimedRoots.reserveCapacity(rejectedRootIDs.count)
          for rootID in rejectedRootIDs {
            guard let root = rejectedRoots.first(where: { $0.id == rootID }),
                  let buildIntent = rejectedIntents.first(where: {
                    $0.id == rootID
                  }) else {
              throw DesignDatabaseRuntimeError.persistedStateCorrupt(
                reason: "A collection completion has an incomplete staging root binding."
              )
            }
            _ = try DesignDatabaseRuntimeRejectedStagingRoot.validate(
              root,
              intent: buildIntent,
              databaseID: operation.databaseID,
              expectedState: .reclaiming,
              using: digester
            )
            reclaimedRoots.append(
              try DesignDatabaseRuntimeStagingRoot.completedReclamation(
                root,
                reachabilityGeneration: completedReachability.generation,
                using: digester
              )
            )
          }
          let revisionIDs = recovered.candidates.revisions.map(
            \.revisionID.description
          )
          let lifecycles = try await transaction.fetch(
            DesignRevisionLifecycleModel.self,
            identifiedBy: revisionIDs,
            consistency: .serializable
          )
          guard lifecycles.count == revisionIDs.count else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A collection sweep completion is missing a revision lifecycle."
            )
          }
          for revision in recovered.candidates.revisions {
            guard let lifecycle = lifecycles.first(where: {
              $0.revisionID == revision.revisionID.description
            }) else {
              throw DesignDatabaseRuntimeError.persistedStateCorrupt(
                reason: "A collection sweep completion has an inconsistent lifecycle set."
              )
            }
            try await transaction.save(
              try DesignDatabaseRuntimeRevisionLifecycle.transitioned(
                lifecycle,
                revision: revision,
                from: .deleting,
                to: .collected,
                reachabilityGeneration: completedReachability.generation,
                using: digester
              ),
              precondition: .exists
            )
          }
          for root in reclaimedRoots {
            try await transaction.save(root, precondition: .exists)
          }
          let completedIntent = try DesignDatabaseRuntimeCollectionIntent
            .advanced(
              intent,
              deletedPhysicalIdentityCount: deletedCount,
              state: .collected,
              completedReachabilityGeneration: completedReachability.generation,
              using: digester
            )
          try await transaction.save(
            completedReachability,
            precondition: .exists
          )
          try await transaction.save(completedIntent, precondition: .exists)
          return completedIntent
        }
        let sweepingIntent = try DesignDatabaseRuntimeCollectionIntent.advanced(
          intent,
          deletedPhysicalIdentityCount: deletedCount,
          state: .sweeping,
          using: digester
        )
        try await transaction.save(sweepingIntent, precondition: .exists)
        return sweepingIntent
      }
      let updated = try await loadCollectionSweep(
        operation: operation,
        requestDigest: requestDigest,
        maximumRevisionCount: maximumRevisionCount,
        maximumPhysicalIdentityCount: maximumPhysicalIdentityCount,
        using: digester
      )
      guard updated.intent.stateDigestAlgorithm
              == updatedIntent.stateDigestAlgorithm,
            updated.intent.stateDigestValue == updatedIntent.stateDigestValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A collection sweep result changed before reconciliation."
        )
      }
      let result = try collectionSweepResult(updated)
      if updated.state == .collected {
        try await releaseCollectionAdmission(updated)
      }
      return result
    } catch DatabaseContextError.commitOutcomeUnknown {
      let reconciled = try await loadCollectionSweep(
        operation: operation,
        requestDigest: requestDigest,
        maximumRevisionCount: maximumRevisionCount,
        maximumPhysicalIdentityCount: maximumPhysicalIdentityCount,
        using: digester
      )
      if reconciled.intent.deletedPhysicalIdentityCount > initialDeletedCount
          || reconciled.state == .collected {
        let result = try collectionSweepResult(reconciled)
        if reconciled.state == .collected {
          try await releaseCollectionAdmission(reconciled)
        }
        return result
      }
      return .outcomeUnknown(
        operation: operation,
        requestDigest: requestDigest
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func loadCollectionSweep(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    maximumRevisionCount: UInt64,
    maximumPhysicalIdentityCount: UInt64,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeLoadedCollectionSweep
  {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
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
        let directory = try await transaction.fetch(
          DesignCollectionPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        return (claim, intent, directory)
      }
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard let claim = persisted.0,
          let intent = persisted.1,
          let directoryModel = persisted.2,
          try DesignDatabaseRuntimeOperationClaim.matches(
            claim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
            requestDigest: requestDigest
          ) else {
      throw .collectionIdempotencyConflict(operation: key)
    }
    let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
      intent,
      maximumRevisionCount: maximumRevisionCount,
      using: digester
    )
    guard recovered.operation == operation,
          recovered.requestDigest == requestDigest else {
      throw .collectionIdempotencyConflict(operation: key)
    }
    let directory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        model: directoryModel,
        operation: operation,
        requestDigest: requestDigest,
        maximumIdentityCount: maximumPhysicalIdentityCount,
        using: digester
      )
    guard recovered.physicalIdentityDirectoryDigest == directory.digest,
          recovered.physicalIdentityCount
            == UInt64(directory.identities.count) else {
      throw .persistedStateCorrupt(
        reason: "A collection sweep intent does not bind its physical identity directory."
      )
    }
    try await validateRejectedStagingRootStates(
      directory: directory,
      collectionState: recovered.state,
      databaseID: operation.databaseID,
      context: databaseContext,
      using: digester
    )
    if recovered.state != .collected {
      let claimStates = try await
        DesignDatabaseRuntimeCollectionPhysicalClaimValidator.validate(
          directory: directory,
          collectionIntentID: key,
          context: databaseContext,
          using: digester
        )
      guard let deletedCount = Int(
        exactly: intent.deletedPhysicalIdentityCount
      ), claimStates.indices.allSatisfy({ index in
        claimStates[index] == (index < deletedCount ? .deleted : .claimed)
      }) else {
        throw .persistedStateCorrupt(
          reason: "A collection sweep claim prefix does not match its intent progress."
        )
      }
    }
    return DesignDatabaseRuntimeLoadedCollectionSweep(
      intent: intent,
      operation: recovered.operation,
      requestDigest: recovered.requestDigest,
      candidates: recovered.candidates,
      originalRootSetDigest: recovered.originalRootSetDigest,
      physicalRootSetDigest: recovered.physicalRootSetDigest,
      physicalIdentityDirectoryDigest: recovered
        .physicalIdentityDirectoryDigest,
      directory: directory,
      state: recovered.state
    )
  }

  package func validateRejectedStagingRootStates(
    directory: DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory,
    collectionState: DesignDatabaseRuntimeCollectionIntent.State,
    databaseID: DesignDatabaseID,
    context: DatabaseContext,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    guard !directory.rejectedStagingRootIDs.isEmpty else { return }
    let persisted: (
      [DesignStagingRootModel],
      [DesignCommitBuildIntentModel]
    )
    do {
      persisted = try await context.withTransaction { transaction in
        let roots = try await transaction.fetch(
          DesignStagingRootModel.self,
          identifiedBy: directory.rejectedStagingRootIDs,
          consistency: .serializable
        )
        let intents = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: directory.rejectedStagingRootIDs,
          consistency: .serializable
        )
        return (roots, intents)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard persisted.0.count == directory.rejectedStagingRootIDs.count,
          persisted.1.count == directory.rejectedStagingRootIDs.count else {
      throw .persistedStateCorrupt(
        reason: "A collection is missing its rejected staging root bindings."
      )
    }
    let expectedState: DesignDatabaseRuntimeStagingRootState =
      collectionState == .collected ? .reclaimed : .reclaiming
    for rootID in directory.rejectedStagingRootIDs {
      guard let root = persisted.0.first(where: { $0.id == rootID }),
            let intent = persisted.1.first(where: { $0.id == rootID }) else {
        throw .persistedStateCorrupt(
          reason: "A collection rejected staging root binding is incomplete."
        )
      }
      _ = try DesignDatabaseRuntimeRejectedStagingRoot.validate(
        root,
        intent: intent,
        databaseID: databaseID,
        expectedState: expectedState,
        using: digester
      )
    }
  }

  private nonisolated func deletePhysicalWrite(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    from transaction: any DatabaseTransactionWriting
  ) async throws(DesignDatabaseRuntimeError) {
    do {
      switch identity.storageType {
      case DesignDatabaseRuntimePhysicalCollectionClaim.projectionNodeStorageType:
        try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
          identity,
          model: DesignProjectionNodeModel.self,
          identifiedBy: identity.modelID,
          expectedIdentity: DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionNodeIdentity,
          from: transaction
        )
      case DesignDatabaseRuntimePhysicalCollectionClaim
        .projectionDescriptorStorageType:
        try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
          identity,
          model: DesignProjectionSemanticDescriptorModel.self,
          identifiedBy: identity.modelID,
          expectedIdentity: DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionDescriptorIdentity,
          from: transaction
        )
      case DesignDatabaseRuntimePhysicalCollectionClaim.projectionBindingStorageType:
        try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
          identity,
          model: DesignProjectionBindingModel.self,
          identifiedBy: identity.modelID,
          expectedIdentity: DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionBindingIdentity,
          from: transaction
        )
      case DesignDatabaseRuntimePhysicalCollectionClaim
        .projectionMaterializationStorageType:
        try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
          identity,
          model: DesignProjectionMaterializationModel.self,
          identifiedBy: identity.modelID,
          expectedIdentity: DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionMaterializationIdentity,
          from: transaction
        )
      default:
        guard let reclaimer = physicalWriteReclaimers[identity.storageType] else {
          throw DesignDatabaseRuntimeError.physicalWriteReclaimerUnavailable(
            storageType: identity.storageType
          )
        }
        try await reclaimer.deleteImmutableWrite(identity, from: transaction)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch let error as DesignDatabaseRuntimePhysicalWriteReclaimerError {
      throw .physicalWriteReclaimFailed(
        identity: identity.modelID,
        reason: String(describing: error)
      )
    } catch {
      throw .physicalWriteReclaimFailed(
        identity: identity.modelID,
        reason: String(describing: error)
      )
    }
  }

  private static func collectionSweepBatch(
    startIndex: Int,
    physicalIdentityCount: Int,
    revisionCount: Int,
    rejectedStagingRootCount: Int,
    maximumPhysicalDeletionCount: UInt64
  ) throws(DesignDatabaseRuntimeError) -> (range: Range<Int>, isTerminal: Bool) {
    guard startIndex >= 0,
          startIndex <= physicalIdentityCount,
          let maximumCount = Int(exactly: maximumPhysicalDeletionCount),
          let lifecycleWriteCount = UInt64(exactly: revisionCount),
          let stagingRootWriteCount = UInt64(
            exactly: rejectedStagingRootCount
          ) else {
      throw .persistedStateCorrupt(
        reason: "A collection sweep batch has an invalid count."
      )
    }
    let remainingCount = physicalIdentityCount - startIndex
    let requestedCount = min(remainingCount, maximumCount)
    let finalWriteCount = UInt64(requestedCount) * 2
      + lifecycleWriteCount + stagingRootWriteCount + 2
    let writeLimit = DesignDatabaseRuntimeCommitBuildIntent
      .stagingTransactionWriteLimit
    if requestedCount == remainingCount,
       finalWriteCount <= writeLimit {
      return (startIndex..<physicalIdentityCount, true)
    }
    guard remainingCount > 1 else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "collection completion transaction writes",
        limit: writeLimit,
        requested: finalWriteCount
      )
    }
    let nonterminalCount = min(requestedCount, remainingCount - 1)
    guard nonterminalCount > 0 else {
      throw .persistedStateCorrupt(
        reason: "A collection sweep batch made no progress."
      )
    }
    return (startIndex..<(startIndex + nonterminalCount), false)
  }

  private nonisolated func collectionSweepResult(
    _ loaded: DesignDatabaseRuntimeLoadedCollectionSweep
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionSweepResult
  {
    let intentStateDigest: ContentDigest
    do {
      intentStateDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: loaded.intent.stateDigestAlgorithm
        ),
        hexadecimalValue: loaded.intent.stateDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A collection sweep has a malformed terminal state digest."
      )
    }
    switch loaded.state {
    case .admitted, .sweeping:
      return .sweeping(
        DesignDatabaseRuntimeCollectionSweepProgress(
          operation: loaded.operation,
          requestDigest: loaded.requestDigest,
          deletedPhysicalIdentityCount: loaded.intent
            .deletedPhysicalIdentityCount,
          physicalIdentityCount: loaded.intent.physicalIdentityCount,
          intentStateDigest: intentStateDigest
        )
      )
    case .collected:
      return .collected(
        DesignDatabaseRuntimeCollectionReceipt(
          operation: loaded.operation,
          requestDigest: loaded.requestDigest,
          candidates: loaded.candidates,
          originalRootSetDigest: loaded.originalRootSetDigest,
          physicalRootSetDigest: loaded.physicalRootSetDigest,
          physicalIdentityDirectoryDigest: loaded
            .physicalIdentityDirectoryDigest,
          physicalIdentityCount: loaded.intent.physicalIdentityCount,
          rejectedStagingRootIDs: loaded.directory.rejectedStagingRootIDs,
          admittedReachabilityGeneration: loaded.intent
            .admittedReachabilityGeneration,
          completedReachabilityGeneration: loaded.intent
            .completedReachabilityGeneration,
          intentStateDigest: intentStateDigest
        )
      )
    }
  }

  private func releaseCollectionAdmission(
    _ loaded: DesignDatabaseRuntimeLoadedCollectionSweep
  ) async throws(DesignDatabaseRuntimeError) {
    try await snapshotLeaseCoordinator.releaseDeletionAdmission(
      DesignDatabaseRuntimeDeletionAdmissionToken(
        identifier: DesignDatabaseRuntimeOperationClaim.key(loaded.operation),
        candidates: loaded.candidates
      )
    )
  }
}
