import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func abandonCommit(
    _ request: DesignCommitAbandonmentRequest,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitAbandonmentResult {
    let digester = SHA256ContentDigester()
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: request.operationID
    )
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        switch try await Self.existingCommitAbandonmentOperation(
          operation: operation,
          requestDigest: request.requestDigest,
          transaction: transaction
        ) {
        case .matching(let model):
          return try Self.commitAbandonmentResult(
            model: model,
            operation: operation,
            requestedDigest: request.requestDigest,
            using: digester
          )
        case .conflict:
          throw DesignDatabaseRuntimeError.commitAbandonmentIdempotencyConflict(
            operation: DesignDatabaseRuntimeOperationClaim.key(operation)
          )
        case .absent:
          break
        }

        let target = try await Self.loadCommitAbandonmentTarget(
          request: request,
          transaction: transaction
        )
        guard let targetClaim = target.claim else {
          try Self.requireAbsentCommitAbandonmentTarget(target)
          return try await Self.persistCommitAbandonmentRejection(
            operation: operation,
            request: request,
            reason: .targetNotRecorded,
            transaction: transaction,
            using: digester
          )
        }
        let actualTargetRequestDigest = try Self.abandonmentContentDigest(
          algorithm: targetClaim.requestDigestAlgorithm,
          value: targetClaim.requestDigestValue,
          field: "target operation request"
        )
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          targetClaim,
          operation: request.targetOperation,
          kind: targetClaim.operationKind,
          requestDigest: actualTargetRequestDigest
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit abandonment target claim is internally inconsistent."
          )
        }
        guard targetClaim.operationKind
                == DesignDatabaseRuntimeOperationClaim.commitKind else {
          return try await Self.persistCommitAbandonmentRejection(
            operation: operation,
            request: request,
            reason: .targetOperationKindMismatch,
            transaction: transaction,
            using: digester
          )
        }
        guard actualTargetRequestDigest == request.targetRequestDigest else {
          return try await Self.persistCommitAbandonmentRejection(
            operation: operation,
            request: request,
            reason: .targetRequestMismatch(actual: actualTargetRequestDigest),
            transaction: transaction,
            using: digester
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          targetClaim,
          operation: request.targetOperation,
          kind: DesignDatabaseRuntimeOperationClaim.commitKind,
          requestDigest: request.targetRequestDigest
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit abandonment target claim changed after exact validation."
          )
        }

        if let targetOutcome = target.outcome {
          let result = try Self.maintenanceCommitResult(
            model: targetOutcome,
            operation: request.targetOperation,
            requestDigest: request.targetRequestDigest,
            using: digester
          )
          let reason: DesignCommitAbandonmentRejection.Reason
          switch result {
          case .committed(let receipt):
            reason = .targetAlreadyCommitted(
              outcomeDigest: receipt.outcomeDigest
            )
          case .rejected(let rejection):
            reason = .targetAlreadyRejected(
              outcomeDigest: rejection.outcomeDigest
            )
          case .outcomeUnknown:
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A persisted commit outcome decoded as unknown."
            )
          }
          return try await Self.persistCommitAbandonmentRejection(
            operation: operation,
            request: request,
            reason: reason,
            transaction: transaction,
            using: digester
          )
        }

        let submission = try Self.recoverCommitAbandonmentSubmission(
          target,
          request: request,
          using: digester
        )
        let reachability = try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        )
        let stagingState = try Self.validateCommitAbandonmentStaging(
          target,
          request: request,
          submission: submission,
          using: digester
        )

        let targetRejection = try Self.maintenanceCommitRejection(
          operation: request.targetOperation,
          submission: submission,
          reason: .abandonedByMaintenance(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: request.reason,
            evidenceDigest: request.evidenceDigest
          ),
          using: digester
        )
        let targetOutcomeModel = try Self.maintenanceCommitOperationModel(
          rejection: targetRejection
        )

        let finalReachability: DesignReachabilityStateModel
        let stagingRootTerminalized: Bool
        if let stagingState {
          finalReachability = try DesignDatabaseRuntimeReachability.advanced(
            reachability,
            kind: "commit abandonment"
          )
          let rejectedIntent = try DesignDatabaseRuntimeCommitBuildIntent
            .advanced(
              stagingState.intent,
              state: .rejected,
              using: digester
            )
          let rejectedRoot = try DesignDatabaseRuntimeStagingRoot.terminalized(
            stagingState.root,
            state: .rejected,
            reachabilityGeneration: finalReachability.generation,
            using: digester
          )
          try await transaction.save(rejectedIntent, precondition: .exists)
          try await transaction.save(rejectedRoot, precondition: .exists)
          try await transaction.save(
            finalReachability,
            precondition: .exists
          )
          stagingRootTerminalized = true
        } else {
          finalReachability = reachability
          stagingRootTerminalized = false
        }
        guard let reachabilityGeneration = UInt64(
          exactly: finalReachability.generation
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit abandonment observed a negative reachability generation."
          )
        }
        let receipt = try Self.commitAbandonmentReceipt(
          operation: operation,
          request: request,
          targetCommitOutcomeDigest: targetRejection.outcomeDigest,
          stagingRootTerminalized: stagingRootTerminalized,
          reachabilityGeneration: reachabilityGeneration,
          using: digester
        )
        try await transaction.save(
          targetOutcomeModel,
          precondition: .notExists
        )
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.commitAbandonmentKind,
            requestDigest: request.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(
          Self.commitAbandonmentOperationModel(receipt: receipt),
          precondition: .notExists
        )
        return .abandoned(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignCommitAbandonmentUnknown(
          operation: operation,
          requestDigest: request.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitAbandonmentTransactionFailed(
        reason: String(describing: error)
      )
    }
  }

  package func commitAbandonmentStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitAbandonmentStatus {
    let digester = SHA256ContentDigester()
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction { transaction in
        switch try await Self.existingCommitAbandonmentOperation(
          operation: operation,
          requestDigest: requestDigest,
          transaction: transaction
        ) {
        case .absent:
          return .notRecorded
        case .conflict:
          throw DesignDatabaseRuntimeError.commitAbandonmentIdempotencyConflict(
            operation: DesignDatabaseRuntimeOperationClaim.key(operation)
          )
        case .matching(let model):
          switch try Self.commitAbandonmentResult(
            model: model,
            operation: operation,
            requestedDigest: requestDigest,
            using: digester
          ) {
          case .abandoned(let receipt):
            return .abandoned(receipt)
          case .rejected(let rejection):
            return .rejected(rejection)
          case .outcomeUnknown(let unknown):
            return .outcomeUnknown(unknown)
          }
        }
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitAbandonmentTransactionFailed(
        reason: String(describing: error)
      )
    }
  }
}

private extension DesignDatabaseRuntimeAttachment {
  static func existingCommitAbandonmentOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    transaction: DatabaseTransaction
  ) async throws -> ExistingCommitAbandonmentOperation {
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    let claim = try await transaction.fetch(
      DesignOperationClaimModel.self,
      identifiedBy: key,
      consistency: .serializable
    )
    let outcome = try await transaction.fetch(
      DesignCommitAbandonmentOperationModel.self,
      identifiedBy: key,
      consistency: .serializable
    )
    guard let claim else {
      guard outcome == nil else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A commit abandonment outcome exists without its operation claim."
        )
      }
      return .absent
    }
    guard try DesignDatabaseRuntimeOperationClaim.matches(
      claim,
      operation: operation,
      kind: DesignDatabaseRuntimeOperationClaim.commitAbandonmentKind,
      requestDigest: requestDigest
    ) else {
      return .conflict
    }
    guard let outcome else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A commit abandonment claim exists without its atomic outcome."
      )
    }
    return .matching(outcome)
  }

  static func loadCommitAbandonmentTarget(
    request: DesignCommitAbandonmentRequest,
    transaction: DatabaseTransaction
  ) async throws -> CommitAbandonmentTargetState {
    let key = DesignDatabaseRuntimeOperationClaim.key(request.targetOperation)
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
    let reservation = try await transaction.fetch(
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
    let intent = try await transaction.fetch(
      DesignCommitBuildIntentModel.self,
      identifiedBy: key,
      consistency: .serializable
    )
    let preparedDirectory = try await transaction.fetch(
      DesignPreparedMutationDirectoryModel.self,
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
    return CommitAbandonmentTargetState(
      claim: claim,
      outcome: outcome,
      reservation: reservation,
      validatedDirectory: validatedDirectory,
      submissionCapsule: submissionCapsule,
      intent: intent,
      preparedDirectory: preparedDirectory,
      stagingRoot: stagingRoot,
      physicalIdentityDirectory: physicalIdentityDirectory
    )
  }

  static func requireAbsentCommitAbandonmentTarget(
    _ target: CommitAbandonmentTargetState
  ) throws(DesignDatabaseRuntimeError) {
    guard target.outcome == nil,
          target.reservation == nil,
          target.validatedDirectory == nil,
          target.submissionCapsule == nil,
          target.intent == nil,
          target.preparedDirectory == nil,
          target.stagingRoot == nil,
          target.physicalIdentityDirectory == nil else {
      throw .persistedStateCorrupt(
        reason: "Commit state exists without its target operation claim."
      )
    }
  }

  static func recoverCommitAbandonmentSubmission(
    _ target: CommitAbandonmentTargetState,
    request: DesignCommitAbandonmentRequest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitSubmission {
    guard let reservation = target.reservation,
          let validatedDirectory = target.validatedDirectory,
          let submissionCapsule = target.submissionCapsule else {
      throw .persistedStateCorrupt(
        reason: "An active commit has no atomic reservation, validation, and submission capsule."
      )
    }
    let validatedDigest = try abandonmentContentDigest(
      algorithm: reservation.validatedDirectoryDigestAlgorithm,
      value: reservation.validatedDirectoryDigestValue,
      field: "validated mutation directory"
    )
    try validateIdentityReservationStatus(
      reservation,
      operation: request.targetOperation,
      requestDigest: request.targetRequestDigest,
      validatedDirectoryDigest: validatedDigest,
      validatedMutationCount: reservation.validatedMutationCount
    )
    try DesignDatabaseRuntimeValidatedMutationDirectory.validateStatus(
      validatedDirectory,
      operation: request.targetOperation,
      requestDigest: request.targetRequestDigest,
      expectedDigest: validatedDigest,
      expectedRecordCount: reservation.validatedMutationCount,
      using: digester
    )
    let planDigest = try abandonmentContentDigest(
      algorithm: reservation.planDigestAlgorithm,
      value: reservation.planDigestValue,
      field: "target plan"
    )
    return try DesignDatabaseRuntimeCommitSubmissionCapsule(
      model: submissionCapsule,
      operation: request.targetOperation,
      expectedRequestDigest: request.targetRequestDigest,
      expectedPlanDigest: planDigest,
      using: digester
    ).submission
  }

  static func validateCommitAbandonmentStaging(
    _ target: CommitAbandonmentTargetState,
    request: DesignCommitAbandonmentRequest,
    submission: DesignCommitSubmission,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> CommitAbandonmentStagingState? {
    guard let intent = target.intent else {
      guard target.preparedDirectory == nil,
            target.stagingRoot == nil,
            target.physicalIdentityDirectory == nil else {
        throw .persistedStateCorrupt(
          reason: "A commit staging directory or root exists without its build intent."
        )
      }
      return nil
    }
    guard let preparedDirectory = target.preparedDirectory,
          let stagingRoot = target.stagingRoot,
          let physicalIdentityDirectory = target.physicalIdentityDirectory else {
      throw .persistedStateCorrupt(
        reason: "An active commit build has an incomplete staging binding."
      )
    }
    let preparedDigest = try abandonmentContentDigest(
      algorithm: intent.preparedDirectoryDigestAlgorithm,
      value: intent.preparedDirectoryDigestValue,
      field: "prepared mutation directory"
    )
    try DesignDatabaseRuntimePreparedMutationDirectory.validateStatus(
      preparedDirectory,
      operation: request.targetOperation,
      requestDigest: request.targetRequestDigest,
      expectedDigest: preparedDigest,
      expectedRecordCount: intent.preparedMutationCount,
      using: digester
    )
    let candidateRevision: DesignRevisionReference
    do {
      candidateRevision = DesignRevisionReference(
        databaseID: request.targetOperation.databaseID,
        revisionID: try DesignRevisionID(
          hexadecimalValue: intent.candidateRevisionID
        )
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment target has a malformed candidate revision."
      )
    }
    let intentState = try DesignDatabaseRuntimeCommitBuildIntent.validateStored(
      intent,
      operation: request.targetOperation,
      submission: submission,
      candidateRevision: candidateRevision,
      using: digester
    )
    guard intentState == .staging || intentState == .prepared else {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment target build is already terminal without an outcome."
      )
    }
    let stagingDigest = try abandonmentContentDigest(
      algorithm: intent.stagingDigestAlgorithm,
      value: intent.stagingDigestValue,
      field: "staging"
    )
    try DesignDatabaseRuntimeStagingRoot.validate(
      stagingRoot,
      operation: request.targetOperation,
      submission: submission,
      candidateRevision: candidateRevision,
      stagingDigest: stagingDigest,
      expectedState: .active,
      using: digester
    )
    let restoredPhysicalDirectory = try
      DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
        model: physicalIdentityDirectory,
        operation: request.targetOperation,
        submission: submission,
        candidateRevision: candidateRevision,
        using: digester
      )
    guard try DesignDatabaseRuntimeStagingRoot
      .physicalIdentityDirectoryDigest(stagingRoot)
        == restoredPhysicalDirectory.digest else {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment target root does not bind its physical directory."
      )
    }
    return CommitAbandonmentStagingState(intent: intent, root: stagingRoot)
  }

  static func persistCommitAbandonmentRejection(
    operation: DesignDatabaseOperationReference,
    request: DesignCommitAbandonmentRequest,
    reason: DesignCommitAbandonmentRejection.Reason,
    transaction: DatabaseTransaction,
    using digester: any ContentDigesting
  ) async throws -> DesignCommitAbandonmentResult {
    let rejection = try commitAbandonmentRejection(
      operation: operation,
      request: request,
      reason: reason,
      using: digester
    )
    try await transaction.save(
      DesignDatabaseRuntimeOperationClaim.make(
        operation: operation,
        kind: DesignDatabaseRuntimeOperationClaim.commitAbandonmentKind,
        requestDigest: request.requestDigest
      ),
      precondition: .notExists
    )
    try await transaction.save(
      commitAbandonmentOperationModel(
        rejection: rejection,
        request: request
      ),
      precondition: .notExists
    )
    return .rejected(rejection)
  }

  static func commitAbandonmentReceipt(
    operation: DesignDatabaseOperationReference,
    request: DesignCommitAbandonmentRequest,
    targetCommitOutcomeDigest: ContentDigest,
    stagingRootTerminalized: Bool,
    reachabilityGeneration: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitAbandonmentReceipt {
    do {
      let outcomeDigest = try DesignCommitAbandonmentDigest.abandonedOutcome(
        operation: operation,
        requestDigest: request.requestDigest,
        targetOperation: request.targetOperation,
        targetRequestDigest: request.targetRequestDigest,
        reason: request.reason,
        evidenceDigest: request.evidenceDigest,
        targetCommitOutcomeDigest: targetCommitOutcomeDigest,
        stagingRootTerminalized: stagingRootTerminalized,
        reachabilityGeneration: reachabilityGeneration,
        using: digester
      )
      return DesignCommitAbandonmentReceipt(
        operation: operation,
        requestDigest: request.requestDigest,
        targetOperation: request.targetOperation,
        targetRequestDigest: request.targetRequestDigest,
        reason: request.reason,
        evidenceDigest: request.evidenceDigest,
        targetCommitOutcomeDigest: targetCommitOutcomeDigest,
        stagingRootTerminalized: stagingRootTerminalized,
        reachabilityGeneration: reachabilityGeneration,
        outcomeDigest: outcomeDigest
      )
    } catch {
      throw .commitAbandonmentTransactionFailed(
        reason: String(describing: error)
      )
    }
  }

  static func commitAbandonmentRejection(
    operation: DesignDatabaseOperationReference,
    request: DesignCommitAbandonmentRequest,
    reason: DesignCommitAbandonmentRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitAbandonmentRejection {
    do {
      let outcomeDigest = try DesignCommitAbandonmentDigest.rejectedOutcome(
        operation: operation,
        requestDigest: request.requestDigest,
        targetOperation: request.targetOperation,
        targetRequestDigest: request.targetRequestDigest,
        abandonmentReason: request.reason,
        evidenceDigest: request.evidenceDigest,
        reason: reason,
        using: digester
      )
      return DesignCommitAbandonmentRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        targetOperation: request.targetOperation,
        targetRequestDigest: request.targetRequestDigest,
        abandonmentReason: request.reason,
        evidenceDigest: request.evidenceDigest,
        reason: reason,
        outcomeDigest: outcomeDigest
      )
    } catch {
      throw .commitAbandonmentTransactionFailed(
        reason: String(describing: error)
      )
    }
  }

  static func commitAbandonmentOperationModel(
    receipt: DesignCommitAbandonmentReceipt
  ) -> DesignCommitAbandonmentOperationModel {
    var model = baseCommitAbandonmentOperationModel(
      operation: receipt.operation,
      requestDigest: receipt.requestDigest,
      targetOperation: receipt.targetOperation,
      targetRequestDigest: receipt.targetRequestDigest,
      reason: receipt.reason,
      evidenceDigest: receipt.evidenceDigest,
      outcomeDigest: receipt.outcomeDigest
    )
    model.outcomeKind = 0
    model.targetCommitOutcomeDigestAlgorithm =
      receipt.targetCommitOutcomeDigest.algorithm.rawValue
    model.targetCommitOutcomeDigestValue =
      receipt.targetCommitOutcomeDigest.hexadecimalValue
    model.stagingRootTerminalized = receipt.stagingRootTerminalized
    model.reachabilityGeneration = Int64(receipt.reachabilityGeneration)
    return model
  }

  static func commitAbandonmentOperationModel(
    rejection: DesignCommitAbandonmentRejection,
    request: DesignCommitAbandonmentRequest
  ) -> DesignCommitAbandonmentOperationModel {
    var model = baseCommitAbandonmentOperationModel(
      operation: rejection.operation,
      requestDigest: rejection.requestDigest,
      targetOperation: rejection.targetOperation,
      targetRequestDigest: rejection.targetRequestDigest,
      reason: request.reason,
      evidenceDigest: request.evidenceDigest,
      outcomeDigest: rejection.outcomeDigest
    )
    model.outcomeKind = 1
    switch rejection.reason {
    case .targetNotRecorded:
      model.rejectionKind = 0
    case .targetOperationKindMismatch:
      model.rejectionKind = 1
    case .targetRequestMismatch(let actual):
      model.rejectionKind = 2
      model.rejectionDigestAlgorithm = actual.algorithm.rawValue
      model.rejectionDigestValue = actual.hexadecimalValue
    case .targetAlreadyCommitted(let outcomeDigest):
      model.rejectionKind = 3
      model.rejectionDigestAlgorithm = outcomeDigest.algorithm.rawValue
      model.rejectionDigestValue = outcomeDigest.hexadecimalValue
    case .targetAlreadyRejected(let outcomeDigest):
      model.rejectionKind = 4
      model.rejectionDigestAlgorithm = outcomeDigest.algorithm.rawValue
      model.rejectionDigestValue = outcomeDigest.hexadecimalValue
    }
    return model
  }

  static func baseCommitAbandonmentOperationModel(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    reason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    outcomeDigest: ContentDigest
  ) -> DesignCommitAbandonmentOperationModel {
    var model = DesignCommitAbandonmentOperationModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    model.targetSubjectScopeID =
      targetOperation.authorizationSubjectScopeID.description
    model.targetOperationID = targetOperation.operationID.rawValue
    model.targetRequestDigestAlgorithm = targetRequestDigest.algorithm.rawValue
    model.targetRequestDigestValue = targetRequestDigest.hexadecimalValue
    model.abandonmentReason = reason.rawValue
    model.evidenceDigestAlgorithm = evidenceDigest.algorithm.rawValue
    model.evidenceDigestValue = evidenceDigest.hexadecimalValue
    model.outcomeDigestAlgorithm = outcomeDigest.algorithm.rawValue
    model.outcomeDigestValue = outcomeDigest.hexadecimalValue
    return model
  }

  static func commitAbandonmentResult(
    model: DesignCommitAbandonmentOperationModel,
    operation: DesignDatabaseOperationReference,
    requestedDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitAbandonmentResult {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestedDigest.algorithm.rawValue,
          model.requestDigestValue == requestedDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment outcome does not match its persisted scope."
      )
    }
    let targetOperation: DesignDatabaseOperationReference
    let targetRequestDigest: ContentDigest
    let abandonmentReason: DesignCommitAbandonmentReason
    let evidenceDigest: ContentDigest
    do {
      targetOperation = DesignDatabaseOperationReference(
        databaseID: operation.databaseID,
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: model.targetSubjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(
          rawValue: model.targetOperationID
        )
      )
      targetRequestDigest = try abandonmentContentDigest(
        algorithm: model.targetRequestDigestAlgorithm,
        value: model.targetRequestDigestValue,
        field: "persisted target request"
      )
      abandonmentReason = try DesignCommitAbandonmentReason(
        rawValue: model.abandonmentReason
      )
      evidenceDigest = try abandonmentContentDigest(
        algorithm: model.evidenceDigestAlgorithm,
        value: model.evidenceDigestValue,
        field: "persisted abandonment evidence"
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment outcome has malformed request fields."
      )
    }
    let canonicalRequestDigest: ContentDigest
    do {
      canonicalRequestDigest = try DesignCommitAbandonmentDigest.request(
        operationID: operation.operationID,
        targetOperation: targetOperation,
        targetRequestDigest: targetRequestDigest,
        reason: abandonmentReason,
        evidenceDigest: evidenceDigest,
        using: digester
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment request digest could not be reconstructed."
      )
    }
    guard canonicalRequestDigest == requestedDigest else {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment request digest is noncanonical."
      )
    }
    let outcomeDigest = try abandonmentContentDigest(
      algorithm: model.outcomeDigestAlgorithm,
      value: model.outcomeDigestValue,
      field: "persisted abandonment outcome"
    )
    switch model.outcomeKind {
    case 0:
      guard let generation = UInt64(exactly: model.reachabilityGeneration) else {
        throw .persistedStateCorrupt(
          reason: "A commit abandonment receipt has a negative reachability generation."
        )
      }
      let targetOutcomeDigest = try abandonmentContentDigest(
        algorithm: model.targetCommitOutcomeDigestAlgorithm,
        value: model.targetCommitOutcomeDigestValue,
        field: "target commit outcome"
      )
      let expectedDigest: ContentDigest
      do {
        expectedDigest = try DesignCommitAbandonmentDigest.abandonedOutcome(
          operation: operation,
          requestDigest: requestedDigest,
          targetOperation: targetOperation,
          targetRequestDigest: targetRequestDigest,
          reason: abandonmentReason,
          evidenceDigest: evidenceDigest,
          targetCommitOutcomeDigest: targetOutcomeDigest,
          stagingRootTerminalized: model.stagingRootTerminalized,
          reachabilityGeneration: generation,
          using: digester
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A commit abandonment receipt digest could not be reconstructed."
        )
      }
      guard expectedDigest == outcomeDigest else {
        throw .persistedStateCorrupt(
          reason: "A commit abandonment receipt digest is inconsistent."
        )
      }
      return .abandoned(
        DesignCommitAbandonmentReceipt(
          operation: operation,
          requestDigest: requestedDigest,
          targetOperation: targetOperation,
          targetRequestDigest: targetRequestDigest,
          reason: abandonmentReason,
          evidenceDigest: evidenceDigest,
          targetCommitOutcomeDigest: targetOutcomeDigest,
          stagingRootTerminalized: model.stagingRootTerminalized,
          reachabilityGeneration: generation,
          outcomeDigest: outcomeDigest
        )
      )
    case 1:
      let rejectionReason = try commitAbandonmentRejectionReason(model)
      let expectedDigest: ContentDigest
      do {
        expectedDigest = try DesignCommitAbandonmentDigest.rejectedOutcome(
          operation: operation,
          requestDigest: requestedDigest,
          targetOperation: targetOperation,
          targetRequestDigest: targetRequestDigest,
          abandonmentReason: abandonmentReason,
          evidenceDigest: evidenceDigest,
          reason: rejectionReason,
          using: digester
        )
      } catch {
        throw .persistedStateCorrupt(
          reason: "A commit abandonment rejection digest could not be reconstructed."
        )
      }
      guard expectedDigest == outcomeDigest else {
        throw .persistedStateCorrupt(
          reason: "A commit abandonment rejection digest is inconsistent."
        )
      }
      return .rejected(
        DesignCommitAbandonmentRejection(
          operation: operation,
          requestDigest: requestedDigest,
          targetOperation: targetOperation,
          targetRequestDigest: targetRequestDigest,
          abandonmentReason: abandonmentReason,
          evidenceDigest: evidenceDigest,
          reason: rejectionReason,
          outcomeDigest: outcomeDigest
        )
      )
    default:
      throw .persistedStateCorrupt(
        reason: "A commit abandonment outcome kind is unsupported."
      )
    }
  }

  static func commitAbandonmentRejectionReason(
    _ model: DesignCommitAbandonmentOperationModel
  ) throws(DesignDatabaseRuntimeError)
    -> DesignCommitAbandonmentRejection.Reason
  {
    switch model.rejectionKind {
    case 0:
      return .targetNotRecorded
    case 1:
      return .targetOperationKindMismatch
    case 2:
      return .targetRequestMismatch(
        actual: try abandonmentContentDigest(
          algorithm: model.rejectionDigestAlgorithm,
          value: model.rejectionDigestValue,
          field: "actual target request"
        )
      )
    case 3:
      return .targetAlreadyCommitted(
        outcomeDigest: try abandonmentContentDigest(
          algorithm: model.rejectionDigestAlgorithm,
          value: model.rejectionDigestValue,
          field: "committed target outcome"
        )
      )
    case 4:
      return .targetAlreadyRejected(
        outcomeDigest: try abandonmentContentDigest(
          algorithm: model.rejectionDigestAlgorithm,
          value: model.rejectionDigestValue,
          field: "rejected target outcome"
        )
      )
    default:
      throw .persistedStateCorrupt(
        reason: "A commit abandonment rejection kind is unsupported."
      )
    }
  }

  static func abandonmentContentDigest(
    algorithm: String,
    value: String,
    field: String
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      return try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: algorithm),
        hexadecimalValue: value
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit abandonment \(field) digest is malformed."
      )
    }
  }
}

private struct CommitAbandonmentTargetState: Sendable {
  let claim: DesignOperationClaimModel?
  let outcome: DesignCommitOperationModel?
  let reservation: DesignIdentityReservationModel?
  let validatedDirectory: DesignValidatedMutationDirectoryModel?
  let submissionCapsule: DesignCommitSubmissionModel?
  let intent: DesignCommitBuildIntentModel?
  let preparedDirectory: DesignPreparedMutationDirectoryModel?
  let stagingRoot: DesignStagingRootModel?
  let physicalIdentityDirectory: DesignStagingPhysicalIdentityDirectoryModel?

  init(
    claim: DesignOperationClaimModel?,
    outcome: DesignCommitOperationModel?,
    reservation: DesignIdentityReservationModel?,
    validatedDirectory: DesignValidatedMutationDirectoryModel?,
    submissionCapsule: DesignCommitSubmissionModel?,
    intent: DesignCommitBuildIntentModel?,
    preparedDirectory: DesignPreparedMutationDirectoryModel?,
    stagingRoot: DesignStagingRootModel?,
    physicalIdentityDirectory: DesignStagingPhysicalIdentityDirectoryModel?
  ) {
    self.claim = claim
    self.outcome = outcome
    self.reservation = reservation
    self.validatedDirectory = validatedDirectory
    self.submissionCapsule = submissionCapsule
    self.intent = intent
    self.preparedDirectory = preparedDirectory
    self.stagingRoot = stagingRoot
    self.physicalIdentityDirectory = physicalIdentityDirectory
  }
}

private struct CommitAbandonmentStagingState: Sendable {
  let intent: DesignCommitBuildIntentModel
  let root: DesignStagingRootModel
}

private enum ExistingCommitAbandonmentOperation {
  case absent
  case matching(DesignCommitAbandonmentOperationModel)
  case conflict
}
