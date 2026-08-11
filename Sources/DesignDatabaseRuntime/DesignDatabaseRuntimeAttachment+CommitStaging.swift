import CircuiteFoundation
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func ensureCommitBuildIntent(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    physicalIdentityDirectory:
      DesignDatabaseRuntimeStagingPhysicalIdentityDirectory,
    stagingDigest: ContentDigest,
    preparedWriteCount: UInt64,
    projectionNodeCount: UInt64,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> Bool {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    let newIntent = try DesignDatabaseRuntimeCommitBuildIntent.make(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectoryDigest: preparedDirectory.digest,
      preparedMutationCount: UInt64(preparedDirectory.records.count),
      stagingDigest: stagingDigest,
      expectedDomainWriteCount: preparedWriteCount,
      expectedProjectionNodeCount: projectionNodeCount,
      using: digester
    )
    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
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
        let storedPhysicalIdentityDirectory = try await transaction.fetch(
          DesignStagingPhysicalIdentityDirectoryModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let storedPreparedDirectory = try await transaction.fetch(
          DesignPreparedMutationDirectoryModel.self,
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
        if let claim {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            claim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitKind,
            requestDigest: submission.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
              operation: key
            )
          }
          if outcome != nil {
            return false
          }
          guard identityReservation != nil, let submissionCapsule else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "An active commit claim has no identity reservation and exact submission capsule."
            )
          }
          _ = try DesignDatabaseRuntimeCommitSubmissionCapsule(
            model: submissionCapsule,
            operation: operation,
            expectedRequestDigest: submission.requestDigest,
            expectedPlanDigest: submission.plan.planDigest,
            using: digester
          )
          if intent == nil {
            guard storedPreparedDirectory == nil,
                  storedPhysicalIdentityDirectory == nil,
                  stagingRoot == nil else {
              throw DesignDatabaseRuntimeError.persistedStateCorrupt(
                reason: "A staging directory or root exists without its build intent."
              )
            }
            let reachability = try await DesignDatabaseRuntimeReachability
              .require(
                databaseID: operation.databaseID,
                transaction: transaction
              )
            let updatedReachability = try DesignDatabaseRuntimeReachability
              .advanced(reachability, kind: "reachability")
            let newStagingRoot = try DesignDatabaseRuntimeStagingRoot.makeActive(
              operation: operation,
              submission: submission,
              candidateRevision: candidateRevision,
              stagingDigest: stagingDigest,
              physicalIdentityDirectoryDigest: physicalIdentityDirectory.digest,
              reachabilityGeneration: updatedReachability.generation,
              using: digester
            )
            try await transaction.save(
              preparedDirectory.model(
                operation: operation,
                submission: submission
              ),
              precondition: .notExists
            )
            try await transaction.save(
              physicalIdentityDirectory.model(
                operation: operation,
                submission: submission,
                candidateRevision: candidateRevision
              ),
              precondition: .notExists
            )
            try await transaction.save(newIntent, precondition: .notExists)
            try await transaction.save(
              newStagingRoot,
              precondition: .notExists
            )
            try await transaction.save(
              updatedReachability,
              precondition: .exists
            )
            return true
          }
          guard let intent else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent disappeared during preparation."
            )
          }
          guard let storedPreparedDirectory else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has no prepared mutation directory."
            )
          }
          guard let storedPhysicalIdentityDirectory else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has no physical identity directory."
            )
          }
          guard let stagingRoot else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent has no active staging root."
            )
          }
          try DesignDatabaseRuntimeStagingRoot.validate(
            stagingRoot,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            stagingDigest: stagingDigest,
            expectedState: .active,
            using: digester
          )
          let restoredDirectory = try DesignDatabaseRuntimePreparedMutationDirectory(
            model: storedPreparedDirectory,
            operation: operation,
            submission: submission,
            using: digester
          )
          guard restoredDirectory.digest == preparedDirectory.digest else {
            throw DesignDatabaseRuntimeError.commitStagingConflict(
              operation: key
            )
          }
          let restoredPhysicalIdentityDirectory = try
            DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
              model: storedPhysicalIdentityDirectory,
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
                  .physicalIdentityDirectoryDigest(stagingRoot)
                  == physicalIdentityDirectory.digest else {
            throw DesignDatabaseRuntimeError.commitStagingConflict(
              operation: key
            )
          }
          let state = try DesignDatabaseRuntimeCommitBuildIntent.validate(
            intent,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            preparedDirectoryDigest: preparedDirectory.digest,
            preparedMutationCount: UInt64(preparedDirectory.records.count),
            stagingDigest: stagingDigest,
            expectedDomainWriteCount: preparedWriteCount,
            expectedProjectionNodeCount: projectionNodeCount,
            using: digester
          )
          guard state == .staging || state == .prepared else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit build intent has no commit outcome."
            )
          }
          return true
        }
        guard outcome == nil,
              intent == nil,
              identityReservation == nil,
              submissionCapsule == nil,
              storedPreparedDirectory == nil,
              storedPhysicalIdentityDirectory == nil,
              stagingRoot == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit outcome or build intent exists without its operation claim."
          )
        }
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "Commit preparation reached staging without an identity reservation."
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  package func stageCommitBuild(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    stagingDigest: ContentDigest,
    prepared: [any DesignDatabaseRuntimePreparedMutation],
    projections: DesignDatabaseRuntimeProjectionStagingDirectory,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let writes = try DesignDatabaseRuntimePreparedWriteDirectory(prepared)
    let projectionNodeCount = projections.totalNodeCount
    try await stagePreparedDomainWrites(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectory: preparedDirectory,
      stagingDigest: stagingDigest,
      writes: writes,
      projectionNodeCount: projectionNodeCount,
      digester: digester
    )
    try await stageProjectionNodes(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectory: preparedDirectory,
      stagingDigest: stagingDigest,
      preparedWriteCount: writes.totalWriteCount,
      projections: projections,
      projectionNodeCount: projectionNodeCount,
      digester: digester
    )
    try await markCommitBuildPrepared(
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectory: preparedDirectory,
      stagingDigest: stagingDigest,
      preparedWriteCount: writes.totalWriteCount,
      projectionNodeCount: projectionNodeCount,
      digester: digester
    )
  }

  private func stagePreparedDomainWrites(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    stagingDigest: ContentDigest,
    writes: DesignDatabaseRuntimePreparedWriteDirectory,
    projectionNodeCount: UInt64,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    while true {
      let advanced: Bool
      do {
        advanced = try await databaseContext.withTransaction(
          configuration: .batch
        ) { transaction in
          guard let intent = try await transaction.fetch(
            DesignCommitBuildIntentModel.self,
            identifiedBy: key,
            consistency: .serializable
          ), let stagingRoot = try await transaction.fetch(
            DesignStagingRootModel.self,
            identifiedBy: key,
            consistency: .serializable
          ) else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent or staging root disappeared during domain staging."
            )
          }
          let state = try DesignDatabaseRuntimeCommitBuildIntent.validate(
            intent,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            preparedDirectoryDigest: preparedDirectory.digest,
            preparedMutationCount: UInt64(preparedDirectory.records.count),
            stagingDigest: stagingDigest,
            expectedDomainWriteCount: writes.totalWriteCount,
            expectedProjectionNodeCount: projectionNodeCount,
            using: digester
          )
          if state == .prepared { return false }
          guard state == .staging else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A terminal commit build intent entered domain staging."
            )
          }
          try DesignDatabaseRuntimeStagingRoot.validate(
            stagingRoot,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            stagingDigest: stagingDigest,
            expectedState: .active,
            using: digester
          )
          let start = intent.stagedDomainWriteCount
          guard start < writes.totalWriteCount else { return false }
          let remaining = writes.totalWriteCount - start
          let count = min(
            remaining,
            DesignDatabaseRuntimeCommitBuildIntent
              .stagingTransactionWriteLimit
          )
          let end = start + count
          for globalIndex in start..<end {
            let write = try writes.resolve(globalIndex)
            try await DesignDatabaseRuntimePhysicalCollectionClaim
              .requireUnclaimed(
                write.identity,
                transaction: transaction,
                using: digester
              )
            try await write.mutation.stageImmutableWrite(
              at: write.localIndex,
              to: transaction
            )
          }
          let reachability = try await DesignDatabaseRuntimeReachability.require(
            databaseID: operation.databaseID,
            transaction: transaction
          )
          let updatedReachability = try DesignDatabaseRuntimeReachability
            .advanced(reachability, kind: "reachability")
          let updated = try DesignDatabaseRuntimeCommitBuildIntent.advanced(
            intent,
            stagedDomainWriteCount: end,
            using: digester
          )
          let updatedStagingRoot = try DesignDatabaseRuntimeStagingRoot
            .advancedActive(
              stagingRoot,
              reachabilityGeneration: updatedReachability.generation,
              using: digester
            )
          try await transaction.save(updated, precondition: .exists)
          try await transaction.save(
            updatedStagingRoot,
            precondition: .exists
          )
          try await transaction.save(
            updatedReachability,
            precondition: .exists
          )
          return true
        }
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .commitTransactionFailed(reason: String(describing: error))
      }
      guard advanced else { return }
    }
  }

  private func stageProjectionNodes(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    stagingDigest: ContentDigest,
    preparedWriteCount: UInt64,
    projections: DesignDatabaseRuntimeProjectionStagingDirectory,
    projectionNodeCount: UInt64,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    while true {
      let advanced: Bool
      do {
        advanced = try await databaseContext.withTransaction(
          configuration: .batch
        ) { transaction in
          guard let intent = try await transaction.fetch(
            DesignCommitBuildIntentModel.self,
            identifiedBy: key,
            consistency: .serializable
          ), let stagingRoot = try await transaction.fetch(
            DesignStagingRootModel.self,
            identifiedBy: key,
            consistency: .serializable
          ) else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A commit build intent or staging root disappeared during projection staging."
            )
          }
          let state = try DesignDatabaseRuntimeCommitBuildIntent.validate(
            intent,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            preparedDirectoryDigest: preparedDirectory.digest,
            preparedMutationCount: UInt64(preparedDirectory.records.count),
            stagingDigest: stagingDigest,
            expectedDomainWriteCount: preparedWriteCount,
            expectedProjectionNodeCount: projectionNodeCount,
            using: digester
          )
          if state == .prepared { return false }
          guard state == .staging,
                intent.stagedDomainWriteCount == preparedWriteCount else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "Projection staging began before domain staging completed."
            )
          }
          try DesignDatabaseRuntimeStagingRoot.validate(
            stagingRoot,
            operation: operation,
            submission: submission,
            candidateRevision: candidateRevision,
            stagingDigest: stagingDigest,
            expectedState: .active,
            using: digester
          )
          let start = intent.stagedProjectionNodeCount
          guard start < projectionNodeCount else { return false }
          let remaining = projectionNodeCount - start
          let count = min(
            remaining,
            DesignDatabaseRuntimeCommitBuildIntent
              .stagingTransactionWriteLimit
          )
          let end = start + count
          for nodeIndex in start..<end {
            let write = try projections.resolve(nodeIndex)
            let projection = write.materialization
            let node = write.node
            let model = write.model
            try await DesignDatabaseRuntimePhysicalCollectionClaim
              .requireUnclaimed(
                try DesignDatabaseRuntimePhysicalCollectionClaim
                  .projectionNodeIdentity(model),
                transaction: transaction,
                using: digester
              )
            if let existing = try await transaction.fetch(
              DesignProjectionNodeModel.self,
              identifiedBy: model.id,
              consistency: .serializable
            ) {
              _ = try DesignProjectionPersistedNodeDecoder.decode(
                existing,
                expectedDigest: node.digest,
                family: projection.descriptor.family,
                reference: projection.reference,
                digester: digester
              )
            } else {
              try await transaction.save(model, precondition: .notExists)
            }
          }
          let reachability = try await DesignDatabaseRuntimeReachability.require(
            databaseID: operation.databaseID,
            transaction: transaction
          )
          let updatedReachability = try DesignDatabaseRuntimeReachability
            .advanced(reachability, kind: "reachability")
          let updated = try DesignDatabaseRuntimeCommitBuildIntent.advanced(
            intent,
            stagedProjectionNodeCount: end,
            using: digester
          )
          let updatedStagingRoot = try DesignDatabaseRuntimeStagingRoot
            .advancedActive(
              stagingRoot,
              reachabilityGeneration: updatedReachability.generation,
              using: digester
            )
          try await transaction.save(updated, precondition: .exists)
          try await transaction.save(
            updatedStagingRoot,
            precondition: .exists
          )
          try await transaction.save(
            updatedReachability,
            precondition: .exists
          )
          return true
        }
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .commitTransactionFailed(reason: String(describing: error))
      }
      guard advanced else { return }
    }
  }

  private func markCommitBuildPrepared(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    stagingDigest: ContentDigest,
    preparedWriteCount: UInt64,
    projectionNodeCount: UInt64,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        guard let intent = try await transaction.fetch(
          DesignCommitBuildIntentModel.self,
          identifiedBy: key,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit build intent disappeared before publication."
          )
        }
        let state = try DesignDatabaseRuntimeCommitBuildIntent.validate(
          intent,
          operation: operation,
          submission: submission,
          candidateRevision: candidateRevision,
          preparedDirectoryDigest: preparedDirectory.digest,
          preparedMutationCount: UInt64(preparedDirectory.records.count),
          stagingDigest: stagingDigest,
          expectedDomainWriteCount: preparedWriteCount,
          expectedProjectionNodeCount: projectionNodeCount,
          using: digester
        )
        if state == .prepared { return }
        guard state == .staging,
              intent.stagedDomainWriteCount == preparedWriteCount,
              intent.stagedProjectionNodeCount == projectionNodeCount else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit build intent was marked prepared before staging completed."
          )
        }
        let updated = try DesignDatabaseRuntimeCommitBuildIntent.advanced(
          intent,
          state: .prepared,
          using: digester
        )
        try await transaction.save(updated, precondition: .exists)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }
}
