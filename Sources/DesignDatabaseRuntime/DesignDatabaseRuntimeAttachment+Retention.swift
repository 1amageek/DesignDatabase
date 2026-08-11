import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func retain(
    _ request: DesignRevisionRetentionRequest,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignRevisionRetentionSubmission {
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
        switch try await Self.existingRetentionOperation(
          operation: operation,
          requestDigest: request.requestDigest,
          transaction: transaction
        ) {
        case .matching(let existing):
          return try Self.retentionSubmission(
            model: existing,
            operation: operation,
            requestedDigest: request.requestDigest,
            using: digester
          )
        case .conflict:
          return .rejected(
            try Self.retentionConflictRejection(
              operation: operation,
              requestDigest: request.requestDigest,
              using: digester
            )
          )
        case .absent:
          break
        }

        guard let revision = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: request.revision.revisionID.description,
          consistency: .serializable
        ), revision.databaseID == databaseID.description else {
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .revisionNotFound,
            transaction: transaction,
            using: digester
          )
        }
        let lifecycle = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: request.revision.revisionID.description,
          consistency: .serializable
        )
        try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
          lifecycle,
          revision: request.revision,
          using: digester
        )

        if let existingClaim = try await transaction.fetch(
          DesignRevisionRetentionModel.self,
          identifiedBy: request.claimID.rawValue,
          consistency: .serializable
        ) {
          guard existingClaim.databaseID == databaseID.description,
                existingClaim.claimID == request.claimID.rawValue else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A retention claim does not match its persisted identity."
            )
          }
          let reason: DesignRevisionRetentionRejection.Reason
          if existingClaim.ownerSubjectScopeID
              != authorizationSubjectScopeID.description {
            reason = .claimUnavailable
          } else if existingClaim.state == 0 {
            reason = .claimAlreadyActive
          } else if existingClaim.state == 1 {
            reason = .claimPermanentlyReleased
          } else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A retention claim state is unsupported."
            )
          }
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: reason,
            transaction: transaction,
            using: digester
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

        var claim = DesignRevisionRetentionModel()
        claim.id = request.claimID.rawValue
        claim.databaseID = databaseID.description
        claim.claimID = request.claimID.rawValue
        claim.ownerSubjectScopeID = authorizationSubjectScopeID.description
        claim.revisionID = request.revision.revisionID.description
        claim.reason = request.reason.rawValue
        claim.evidenceDigestAlgorithm = request.evidenceDigest.algorithm.rawValue
        claim.evidenceDigestValue = request.evidenceDigest.hexadecimalValue
        claim.generation = 1
        claim.state = 0

        let receipt = try Self.retentionReceipt(
          operation: operation,
          requestDigest: request.requestDigest,
          claimID: request.claimID,
          revision: request.revision,
          generation: 1,
          reachabilityGeneration: UInt64(updatedReachability.generation),
          state: .active,
          using: digester
        )
        let operationModel = Self.retentionOperationModel(
          receipt: receipt,
          requestDigest: request.requestDigest
        )
        try await transaction.save(claim, precondition: .notExists)
        try await transaction.save(updatedReachability, precondition: .exists)
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.retentionKind,
            requestDigest: request.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(operationModel, precondition: .notExists)
        return .applied(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignRevisionRetentionUnknown(
          operation: operation,
          requestDigest: request.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .retentionTransactionFailed(reason: String(describing: error))
    }
  }

  package func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignRevisionRetentionSubmission {
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
        switch try await Self.existingRetentionOperation(
          operation: operation,
          requestDigest: request.requestDigest,
          transaction: transaction
        ) {
        case .matching(let existing):
          return try Self.retentionSubmission(
            model: existing,
            operation: operation,
            requestedDigest: request.requestDigest,
            using: digester
          )
        case .conflict:
          return .rejected(
            try Self.retentionConflictRejection(
              operation: operation,
              requestDigest: request.requestDigest,
              using: digester
            )
          )
        case .absent:
          break
        }

        guard var claim = try await transaction.fetch(
          DesignRevisionRetentionModel.self,
          identifiedBy: request.claimID.rawValue,
          consistency: .serializable
        ) else {
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .claimUnavailable,
            transaction: transaction,
            using: digester
          )
        }
        guard claim.databaseID == databaseID.description,
              claim.claimID == request.claimID.rawValue else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A retention claim does not match its persisted identity."
          )
        }
        guard claim.ownerSubjectScopeID == authorizationSubjectScopeID.description else {
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .claimUnavailable,
            transaction: transaction,
            using: digester
          )
        }
        guard claim.state == 0 else {
          guard claim.state == 1 else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A retention claim state is unsupported."
            )
          }
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .claimPermanentlyReleased,
            transaction: transaction,
            using: digester
          )
        }
        guard claim.revisionID == request.expectedRevision.revisionID.description else {
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .revisionMismatch,
            transaction: transaction,
            using: digester
          )
        }
        guard let claimGeneration = UInt64(exactly: claim.generation) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A retention claim generation is malformed."
          )
        }
        guard claimGeneration == request.expectedGeneration else {
          return try await Self.persistRetentionRejection(
            operation: operation,
            requestDigest: request.requestDigest,
            reason: .generationMismatch(actual: claimGeneration),
            transaction: transaction,
            using: digester
          )
        }
        let nextClaimGeneration = try Self.incrementedGeneration(
          claim.generation,
          kind: "retention claim"
        )
        let reachability = try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        )
        let updatedReachability = try DesignDatabaseRuntimeReachability.advanced(
          reachability,
          kind: "reachability"
        )
        claim.generation = nextClaimGeneration
        claim.state = 1

        let receipt = try Self.retentionReceipt(
          operation: operation,
          requestDigest: request.requestDigest,
          claimID: request.claimID,
          revision: request.expectedRevision,
          generation: UInt64(nextClaimGeneration),
          reachabilityGeneration: UInt64(updatedReachability.generation),
          state: .released,
          using: digester
        )
        let operationModel = Self.retentionOperationModel(
          receipt: receipt,
          requestDigest: request.requestDigest
        )
        try await transaction.save(claim, precondition: .exists)
        try await transaction.save(updatedReachability, precondition: .exists)
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.retentionKind,
            requestDigest: request.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(operationModel, precondition: .notExists)
        return .applied(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignRevisionRetentionUnknown(
          operation: operation,
          requestDigest: request.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .retentionTransactionFailed(reason: String(describing: error))
    }
  }

  package func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignRevisionRetentionStatus {
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction { transaction in
        switch try await Self.existingRetentionOperation(
          operation: operation,
          requestDigest: requestDigest,
          transaction: transaction
        ) {
        case .absent:
          return .notRecorded
        case .conflict:
          return .rejected(
            try Self.retentionConflictRejection(
              operation: operation,
              requestDigest: requestDigest,
              using: digester
            )
          )
        case .matching(let model):
          switch try Self.retentionSubmission(
            model: model,
            operation: operation,
            requestedDigest: requestDigest,
            using: digester
          ) {
          case .applied(let receipt):
            return .applied(receipt)
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
      throw .retentionTransactionFailed(reason: String(describing: error))
    }
  }

  private static func existingRetentionOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    transaction: DatabaseTransaction
  ) async throws -> ExistingRetentionOperation {
    let key = retentionOperationKey(operation)
    let claim = try await transaction.fetch(
      DesignOperationClaimModel.self,
      identifiedBy: key,
      consistency: .serializable
    )
    let outcome = try await transaction.fetch(
      DesignRetentionOperationModel.self,
      identifiedBy: key,
      consistency: .serializable
    )
    guard let claim else {
      guard outcome == nil else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention operation outcome exists without its claim."
        )
      }
      return .absent
    }
    guard try DesignDatabaseRuntimeOperationClaim.matches(
      claim,
      operation: operation,
      kind: DesignDatabaseRuntimeOperationClaim.retentionKind,
      requestDigest: requestDigest
    ) else {
      return .conflict
    }
    guard let outcome else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A retention operation claim exists without its outcome."
      )
    }
    return .matching(outcome)
  }

  private static func retentionSubmission(
    model: DesignRetentionOperationModel,
    operation: DesignDatabaseOperationReference,
    requestedDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws -> DesignRevisionRetentionSubmission {
    let operationKey = retentionOperationKey(operation)
    guard model.id == operationKey,
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A retention operation does not match its persisted scope."
      )
    }
    guard model.requestDigestAlgorithm == requestedDigest.algorithm.rawValue,
          model.requestDigestValue == requestedDigest.hexadecimalValue else {
      return .rejected(
        try retentionConflictRejection(
          operation: operation,
          requestDigest: requestedDigest,
          using: digester
        )
      )
    }
    let persistedRequestDigest = requestedDigest
    let outcomeDigest: ContentDigest
    do {
      outcomeDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: model.outcomeDigestAlgorithm),
        hexadecimalValue: model.outcomeDigestValue
      )
    } catch {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A retention operation outcome digest is malformed."
      )
    }
    switch model.outcomeKind {
    case 0:
      let claimID: DesignRevisionRetentionID
      let revision: DesignRevisionReference
      do {
        claimID = try DesignRevisionRetentionID(rawValue: model.claimID)
        revision = DesignRevisionReference(
          databaseID: operation.databaseID,
          revisionID: try DesignRevisionID(hexadecimalValue: model.revisionID)
        )
      } catch {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention receipt identity is malformed."
        )
      }
      guard let generation = UInt64(exactly: model.generation),
            let reachabilityGeneration = UInt64(
              exactly: model.reachabilityGeneration
            ) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention receipt generation is malformed."
        )
      }
      let state: DesignRevisionRetentionState
      if model.retentionState == 0 {
        state = .active
      } else if model.retentionState == 1 {
        state = .released
      } else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention receipt state is unsupported."
        )
      }
      let expectedDigest = try DesignRevisionRetentionDigest.appliedOutcome(
        operation: operation,
        requestDigest: persistedRequestDigest,
        claimID: claimID,
        revision: revision,
        generation: generation,
        reachabilityGeneration: reachabilityGeneration,
        state: state,
        using: digester
      )
      guard outcomeDigest == expectedDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention receipt digest is inconsistent."
        )
      }
      return .applied(
        DesignRevisionRetentionReceipt(
          operation: operation,
          claimID: claimID,
          revision: revision,
          generation: generation,
          reachabilityGeneration: reachabilityGeneration,
          state: state,
          outcomeDigest: outcomeDigest
        )
      )
    case 1:
      let reason = try retentionRejectionReason(model)
      let expectedDigest = try DesignRevisionRetentionDigest.rejectedOutcome(
        operation: operation,
        requestDigest: persistedRequestDigest,
        reason: reason,
        using: digester
      )
      guard outcomeDigest == expectedDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention rejection digest is inconsistent."
        )
      }
      return .rejected(
        DesignRevisionRetentionRejection(
          operation: operation,
          requestDigest: persistedRequestDigest,
          reason: reason,
          outcomeDigest: outcomeDigest
        )
      )
    default:
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A retention operation outcome kind is unsupported."
      )
    }
  }

  private static func persistRetentionRejection(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    reason: DesignRevisionRetentionRejection.Reason,
    transaction: DatabaseTransaction,
    using digester: any ContentDigesting
  ) async throws -> DesignRevisionRetentionSubmission {
    let outcomeDigest = try DesignRevisionRetentionDigest.rejectedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      using: digester
    )
    let rejection = DesignRevisionRetentionRejection(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      outcomeDigest: outcomeDigest
    )
    let model = retentionOperationModel(rejection: rejection)
    try await transaction.save(
      DesignDatabaseRuntimeOperationClaim.make(
        operation: operation,
        kind: DesignDatabaseRuntimeOperationClaim.retentionKind,
        requestDigest: requestDigest
      ),
      precondition: .notExists
    )
    try await transaction.save(model, precondition: .notExists)
    return .rejected(rejection)
  }

  private static func retentionConflictRejection(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws -> DesignRevisionRetentionRejection {
    let reason = DesignRevisionRetentionRejection.Reason.operationRequestConflict
    return DesignRevisionRetentionRejection(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      outcomeDigest: try DesignRevisionRetentionDigest.rejectedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        reason: reason,
        using: digester
      )
    )
  }

  private static func retentionReceipt(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    generation: UInt64,
    reachabilityGeneration: UInt64,
    state: DesignRevisionRetentionState,
    using digester: any ContentDigesting
  ) throws -> DesignRevisionRetentionReceipt {
    let outcomeDigest = try DesignRevisionRetentionDigest.appliedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      claimID: claimID,
      revision: revision,
      generation: generation,
      reachabilityGeneration: reachabilityGeneration,
      state: state,
      using: digester
    )
    return DesignRevisionRetentionReceipt(
      operation: operation,
      claimID: claimID,
      revision: revision,
      generation: generation,
      reachabilityGeneration: reachabilityGeneration,
      state: state,
      outcomeDigest: outcomeDigest
    )
  }

  private static func retentionOperationModel(
    receipt: DesignRevisionRetentionReceipt,
    requestDigest: ContentDigest
  ) -> DesignRetentionOperationModel {
    var model = retentionOperationModel(
      operation: receipt.operation,
      requestDigest: requestDigest,
      outcomeDigest: receipt.outcomeDigest
    )
    model.outcomeKind = 0
    model.claimID = receipt.claimID.rawValue
    model.revisionID = receipt.revision.revisionID.description
    model.generation = Int64(receipt.generation)
    model.reachabilityGeneration = Int64(receipt.reachabilityGeneration)
    model.retentionState = receipt.state == .active ? 0 : 1
    return model
  }

  private static func retentionOperationModel(
    rejection: DesignRevisionRetentionRejection
  ) -> DesignRetentionOperationModel {
    var model = retentionOperationModel(
      operation: rejection.operation,
      requestDigest: rejection.requestDigest,
      outcomeDigest: rejection.outcomeDigest
    )
    model.outcomeKind = 1
    switch rejection.reason {
    case .operationRequestConflict:
      model.rejectionKind = 0
    case .claimUnavailable:
      model.rejectionKind = 1
    case .claimAlreadyActive:
      model.rejectionKind = 2
    case .claimPermanentlyReleased:
      model.rejectionKind = 3
    case .revisionNotFound:
      model.rejectionKind = 4
    case .revisionMismatch:
      model.rejectionKind = 5
    case .generationMismatch(let actual):
      model.rejectionKind = 6
      model.rejectionActualGeneration = Int64(actual)
    }
    return model
  }

  private static func retentionOperationModel(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    outcomeDigest: ContentDigest
  ) -> DesignRetentionOperationModel {
    var model = DesignRetentionOperationModel()
    model.id = retentionOperationKey(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    model.outcomeDigestAlgorithm = outcomeDigest.algorithm.rawValue
    model.outcomeDigestValue = outcomeDigest.hexadecimalValue
    return model
  }

  private static func retentionRejectionReason(
    _ model: DesignRetentionOperationModel
  ) throws -> DesignRevisionRetentionRejection.Reason {
    switch model.rejectionKind {
    case 0:
      return .operationRequestConflict
    case 1:
      return .claimUnavailable
    case 2:
      return .claimAlreadyActive
    case 3:
      return .claimPermanentlyReleased
    case 4:
      return .revisionNotFound
    case 5:
      return .revisionMismatch
    case 6:
      guard let actual = UInt64(exactly: model.rejectionActualGeneration) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A retention rejection generation is malformed."
        )
      }
      return .generationMismatch(actual: actual)
    default:
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A retention rejection kind is unsupported."
      )
    }
  }

  private static func incrementedGeneration(
    _ value: Int64,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> Int64 {
    guard value >= 0, value < Int64.max else {
      throw .generationExhausted(kind: kind)
    }
    return value + 1
  }

  private static func retentionOperationKey(
    _ operation: DesignDatabaseOperationReference
  ) -> String {
    operation.databaseID.description
      + ":" + operation.authorizationSubjectScopeID.description
      + ":" + operation.operationID.rawValue
  }
}

private enum ExistingRetentionOperation {
  case absent
  case matching(DesignRetentionOperationModel)
  case conflict
}
