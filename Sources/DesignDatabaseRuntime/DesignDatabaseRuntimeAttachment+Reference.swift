import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func resolve(
    _ selector: DesignRevisionSelector,
    expectedDatabaseID: DesignDatabaseID
  ) async throws(DesignDatabaseRuntimeError) -> DesignRevisionReference {
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction { transaction in
        let revision: DesignRevisionReference
        switch selector {
        case .exact(let exact):
          guard exact.databaseID == expectedDatabaseID else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "An exact selector crossed the attached database boundary."
            )
          }
          revision = exact
        case .named(let name):
          guard let reference = try await transaction.fetch(
            DesignNamedReferenceModel.self,
            identifiedBy: name.rawValue,
            consistency: .serializable
          ), reference.databaseID == expectedDatabaseID.description,
             !reference.revisionID.isEmpty else {
            throw DesignDatabaseRuntimeError.namedReferenceNotFound(name.rawValue)
          }
          guard UInt64(exactly: reference.generation) != nil else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A named reference generation is malformed."
            )
          }
          do {
            revision = DesignRevisionReference(
              databaseID: expectedDatabaseID,
              revisionID: try DesignRevisionID(
                hexadecimalValue: reference.revisionID
              )
            )
          } catch {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A named reference contains a malformed revision identity."
            )
          }
        }
        guard let manifest = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: revision.revisionID.description,
          consistency: .serializable
        ), manifest.databaseID == expectedDatabaseID.description else {
          throw DesignDatabaseRuntimeError.revisionNotFound(
            revision.revisionID.description
          )
        }
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
        return revision
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .referenceTransactionFailed(reason: String(describing: error))
    }
  }

  package func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignReferenceUpdateResult {
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: request.operationID
    )
    let operationKey = Self.referenceOperationKey(operation)
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction(
        configuration: .batch
      ) { transaction in
        let operationClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        let existing = try await transaction.fetch(
          DesignReferenceOperationModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        if let operationClaim {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            operationClaim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.referenceKind,
            requestDigest: request.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError.referenceIdempotencyConflict(
              operation: operationKey
            )
          }
          guard let existing else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A reference operation claim exists without its outcome."
            )
          }
          return try Self.referenceResult(
            model: existing,
            operation: operation,
            requestDigest: request.requestDigest,
            using: digester
          )
        }
        guard existing == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A reference operation outcome exists without its claim."
          )
        }

        let reference = try await transaction.fetch(
          DesignNamedReferenceModel.self,
          identifiedBy: request.name.rawValue,
          consistency: .serializable
        )
        let actualRevision = try Self.referenceRevision(
          reference,
          expectedDatabaseID: databaseID
        )
        let actualGeneration = try Self.referenceGeneration(reference)
        guard actualGeneration == request.expectedGeneration,
              actualRevision == request.expectedRevision else {
          let reason = DesignReferenceUpdateRejection.Reason.preconditionMismatch(
            actualGeneration: actualGeneration,
            actualRevision: actualRevision
          )
          let rejection = try Self.referenceRejection(
            operation: operation,
            request: request,
            reason: reason,
            using: digester
          )
          let model = Self.referenceOperationModel(
            rejection: rejection,
            request: request
          )
          try await transaction.save(
            DesignDatabaseRuntimeOperationClaim.make(
              operation: operation,
              kind: DesignDatabaseRuntimeOperationClaim.referenceKind,
              requestDigest: request.requestDigest
            ),
            precondition: .notExists
          )
          try await transaction.save(model, precondition: .notExists)
          return .rejected(rejection)
        }

        if let desired = request.desiredRevision {
          guard let manifest = try await transaction.fetch(
            DesignRevisionManifestModel.self,
            identifiedBy: desired.revisionID.description,
            consistency: .serializable
          ), manifest.databaseID == databaseID.description else {
            let reason = DesignReferenceUpdateRejection.Reason
              .desiredRevisionNotFound(desired)
            let rejection = try Self.referenceRejection(
              operation: operation,
              request: request,
              reason: reason,
              using: digester
            )
            let model = Self.referenceOperationModel(
              rejection: rejection,
              request: request
            )
            try await transaction.save(
              DesignDatabaseRuntimeOperationClaim.make(
                operation: operation,
                kind: DesignDatabaseRuntimeOperationClaim.referenceKind,
                requestDigest: request.requestDigest
              ),
              precondition: .notExists
            )
            try await transaction.save(model, precondition: .notExists)
            return .rejected(rejection)
          }
          let lifecycle = try await transaction.fetch(
            DesignRevisionLifecycleModel.self,
            identifiedBy: desired.revisionID.description,
            consistency: .serializable
          )
          try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
            lifecycle,
            revision: desired,
            using: digester
          )
        }

        guard actualGeneration < UInt64(Int64.max) else {
          throw DesignDatabaseRuntimeError.generationExhausted(
            kind: "named reference"
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
        let nextGeneration = actualGeneration + 1
        var updated = reference ?? DesignNamedReferenceModel()
        updated.id = request.name.rawValue
        updated.databaseID = databaseID.description
        updated.revisionID = request.desiredRevision?.revisionID.description ?? ""
        updated.generation = Int64(nextGeneration)

        let outcomeDigest = try DesignReferenceUpdateDigest.appliedOutcome(
          operation: operation,
          requestDigest: request.requestDigest,
          name: request.name,
          previousRevision: actualRevision,
          currentRevision: request.desiredRevision,
          generation: nextGeneration,
          using: digester
        )
        let receipt = DesignReferenceUpdateReceipt(
          operation: operation,
          name: request.name,
          previousRevision: actualRevision,
          currentRevision: request.desiredRevision,
          generation: nextGeneration,
          outcomeDigest: outcomeDigest
        )
        let model = Self.referenceOperationModel(
          receipt: receipt,
          request: request
        )
        try await transaction.save(
          updated,
          precondition: reference == nil ? .notExists : .exists
        )
        try await transaction.save(
          updatedReachability,
          precondition: .exists
        )
        try await transaction.save(
          DesignDatabaseRuntimeOperationClaim.make(
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.referenceKind,
            requestDigest: request.requestDigest
          ),
          precondition: .notExists
        )
        try await transaction.save(model, precondition: .notExists)
        return .applied(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignReferenceUpdateUnknown(
          operation: operation,
          requestDigest: request.requestDigest
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .referenceTransactionFailed(reason: String(describing: error))
    }
  }

  package func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignReferenceUpdateStatus {
    let databaseContext = try context()
    do {
      return try await databaseContext.withTransaction { transaction in
        let operationKey = Self.referenceOperationKey(operation)
        let operationClaim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        let model = try await transaction.fetch(
          DesignReferenceOperationModel.self,
          identifiedBy: operationKey,
          consistency: .serializable
        )
        guard operationClaim != nil || model != nil else {
          return .notRecorded
        }
        guard let operationClaim, let model else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A reference operation claim and outcome are not atomic."
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          operationClaim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.referenceKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError.referenceIdempotencyConflict(
            operation: operationKey
          )
        }
        switch try Self.referenceResult(
          model: model,
          operation: operation,
          requestDigest: requestDigest,
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
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .referenceTransactionFailed(reason: String(describing: error))
    }
  }

  private static func referenceResult(
    model: DesignReferenceOperationModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws -> DesignReferenceUpdateResult {
    let operationKey = referenceOperationKey(operation)
    guard model.id == operationKey,
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A reference operation does not match its persisted scope."
      )
    }
    guard model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue else {
      throw DesignDatabaseRuntimeError.referenceIdempotencyConflict(
        operation: operationKey
      )
    }
    let name: DesignReferenceName
    let outcomeDigest: ContentDigest
    do {
      name = try DesignReferenceName(rawValue: model.referenceName)
      outcomeDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: model.outcomeDigestAlgorithm),
        hexadecimalValue: model.outcomeDigestValue
      )
    } catch {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A reference operation contains a malformed identity or digest."
      )
    }

    switch model.outcomeKind {
    case 0:
      let previous = try optionalRevision(
        model.previousRevisionID,
        databaseID: operation.databaseID
      )
      let current = try optionalRevision(
        model.currentRevisionID,
        databaseID: operation.databaseID
      )
      guard let generation = UInt64(exactly: model.generation) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A reference operation generation is malformed."
        )
      }
      let expectedDigest = try DesignReferenceUpdateDigest.appliedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        name: name,
        previousRevision: previous,
        currentRevision: current,
        generation: generation,
        using: digester
      )
      guard outcomeDigest == expectedDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A reference operation receipt digest is inconsistent."
        )
      }
      return .applied(
        DesignReferenceUpdateReceipt(
          operation: operation,
          name: name,
          previousRevision: previous,
          currentRevision: current,
          generation: generation,
          outcomeDigest: outcomeDigest
        )
      )
    case 1:
      let reason: DesignReferenceUpdateRejection.Reason
      switch model.rejectionKind {
      case 0:
        guard let generation = UInt64(exactly: model.generation) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A reference rejection generation is malformed."
          )
        }
        reason = .preconditionMismatch(
          actualGeneration: generation,
          actualRevision: try optionalRevision(
            model.rejectionRevisionID,
            databaseID: operation.databaseID
          )
        )
      case 1:
        guard let revision = try optionalRevision(
          model.rejectionRevisionID,
          databaseID: operation.databaseID
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A missing-revision rejection omits its revision."
          )
        }
        reason = .desiredRevisionNotFound(revision)
      default:
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A reference rejection kind is unsupported."
        )
      }
      let expectedDigest = try DesignReferenceUpdateDigest.rejectedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        name: name,
        reason: reason,
        using: digester
      )
      guard outcomeDigest == expectedDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A reference rejection digest is inconsistent."
        )
      }
      return .rejected(
        DesignReferenceUpdateRejection(
          operation: operation,
          name: name,
          requestDigest: requestDigest,
          reason: reason,
          outcomeDigest: outcomeDigest
        )
      )
    default:
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A reference operation outcome kind is unsupported."
      )
    }
  }

  private static func referenceRejection(
    operation: DesignDatabaseOperationReference,
    request: DesignReferenceUpdateRequest,
    reason: DesignReferenceUpdateRejection.Reason,
    using digester: any ContentDigesting
  ) throws -> DesignReferenceUpdateRejection {
    let outcomeDigest = try DesignReferenceUpdateDigest.rejectedOutcome(
      operation: operation,
      requestDigest: request.requestDigest,
      name: request.name,
      reason: reason,
      using: digester
    )
    return DesignReferenceUpdateRejection(
      operation: operation,
      name: request.name,
      requestDigest: request.requestDigest,
      reason: reason,
      outcomeDigest: outcomeDigest
    )
  }

  private static func referenceOperationModel(
    receipt: DesignReferenceUpdateReceipt,
    request: DesignReferenceUpdateRequest
  ) -> DesignReferenceOperationModel {
    var model = referenceOperationModel(
      operation: receipt.operation,
      request: request,
      name: receipt.name,
      outcomeDigest: receipt.outcomeDigest
    )
    model.outcomeKind = 0
    model.previousRevisionID = receipt.previousRevision?.revisionID.description ?? ""
    model.currentRevisionID = receipt.currentRevision?.revisionID.description ?? ""
    model.generation = Int64(receipt.generation)
    return model
  }

  private static func referenceOperationModel(
    rejection: DesignReferenceUpdateRejection,
    request: DesignReferenceUpdateRequest
  ) -> DesignReferenceOperationModel {
    var model = referenceOperationModel(
      operation: rejection.operation,
      request: request,
      name: rejection.name,
      outcomeDigest: rejection.outcomeDigest
    )
    model.outcomeKind = 1
    switch rejection.reason {
    case .preconditionMismatch(let generation, let revision):
      model.rejectionKind = 0
      model.generation = Int64(generation)
      model.rejectionRevisionID = revision?.revisionID.description ?? ""
    case .desiredRevisionNotFound(let revision):
      model.rejectionKind = 1
      model.rejectionRevisionID = revision.revisionID.description
    }
    return model
  }

  private static func referenceOperationModel(
    operation: DesignDatabaseOperationReference,
    request: DesignReferenceUpdateRequest,
    name: DesignReferenceName,
    outcomeDigest: ContentDigest
  ) -> DesignReferenceOperationModel {
    var model = DesignReferenceOperationModel()
    model.id = referenceOperationKey(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = request.requestDigest.algorithm.rawValue
    model.requestDigestValue = request.requestDigest.hexadecimalValue
    model.referenceName = name.rawValue
    model.outcomeDigestAlgorithm = outcomeDigest.algorithm.rawValue
    model.outcomeDigestValue = outcomeDigest.hexadecimalValue
    return model
  }

  private static func referenceRevision(
    _ model: DesignNamedReferenceModel?,
    expectedDatabaseID: DesignDatabaseID
  ) throws -> DesignRevisionReference? {
    guard let model else { return nil }
    guard model.databaseID == expectedDatabaseID.description else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A named reference belongs to another database."
      )
    }
    return try optionalRevision(
      model.revisionID,
      databaseID: expectedDatabaseID
    )
  }

  private static func referenceGeneration(
    _ model: DesignNamedReferenceModel?
  ) throws -> UInt64 {
    guard let model else { return 0 }
    guard let generation = UInt64(exactly: model.generation) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A named reference generation is malformed."
      )
    }
    return generation
  }

  private static func optionalRevision(
    _ rawValue: String,
    databaseID: DesignDatabaseID
  ) throws -> DesignRevisionReference? {
    guard !rawValue.isEmpty else { return nil }
    do {
      return DesignRevisionReference(
        databaseID: databaseID,
        revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
      )
    } catch {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A persisted reference revision is malformed."
      )
    }
  }

  private static func referenceOperationKey(
    _ operation: DesignDatabaseOperationReference
  ) -> String {
    operation.databaseID.description
      + ":" + operation.authorizationSubjectScopeID.description
      + ":" + operation.operationID.rawValue
  }
}
