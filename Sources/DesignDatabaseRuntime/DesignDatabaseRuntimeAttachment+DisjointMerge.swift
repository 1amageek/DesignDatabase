import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import Foundation

extension DesignDatabaseRuntimeAttachment {
  package func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission,
    validatedCommitReceipt: DesignCommitReceipt,
    assessmentMatches: Bool,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDisjointMergePublicationResult
  {
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    switch try await disjointMergePublicationStatus(
      operation: operation,
      requestDigest: submission.requestDigest,
      digester: digester
    ) {
    case .published(let receipt):
      return .published(receipt)
    case .rejected(let rejection):
      return .rejected(rejection)
    case .notRecorded:
      break
    case .outcomeUnknown(let unknown):
      return .outcomeUnknown(unknown)
    }

    let candidateDigest: ContentDigest
    do {
      candidateDigest = try DesignDisjointMergePublicationDigest.candidate(
        submission.candidate,
        using: digester
      )
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    let candidateRevision = try Self.disjointMergeCandidateRevision(
      operation: operation,
      requestDigest: submission.requestDigest
    )
    let context = try context()
    do {
      return try await context.withTransaction(
        configuration: .batch
      ) { transaction in
        let key = DesignDatabaseRuntimeOperationClaim.key(operation)
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let outcome = try await transaction.fetch(
          DesignDisjointMergeOperationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        if let claim {
          guard try DesignDatabaseRuntimeOperationClaim.matches(
            claim,
            operation: operation,
            kind: DesignDatabaseRuntimeOperationClaim.disjointMergeKind,
            requestDigest: submission.requestDigest
          ) else {
            throw DesignDatabaseRuntimeError
              .disjointMergeIdempotencyConflict(operation: key)
          }
          guard let outcome else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A disjoint-merge claim has no atomic outcome."
            )
          }
          return try Self.disjointMergeResult(
            model: outcome,
            operation: operation,
            requestDigest: submission.requestDigest,
            using: digester
          )
        }
        guard outcome == nil else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A disjoint-merge outcome has no atomic claim."
          )
        }

        let authenticatedValidatedCommitReceipt = try await Self
          .authenticatedValidatedCommitReceipt(
            submission: submission,
            expectedReceipt: validatedCommitReceipt,
            databaseID: databaseID,
            authorizationSubjectScopeID: authorizationSubjectScopeID,
            transaction: transaction,
            using: digester
          )

        if !assessmentMatches {
          let rejection = try Self.disjointMergeRejection(
            operation: operation,
            submission: submission,
            candidateDigest: candidateDigest,
            reason: .assessmentChanged,
            using: digester
          )
          try await Self.saveDisjointMergeOutcome(
            .rejected(rejection),
            operation: operation,
            requestDigest: submission.requestDigest,
            transaction: transaction,
            using: digester
          )
          return .rejected(rejection)
        }

        let requiredRevisions = Set(
          [submission.candidate.baseRevision]
            + submission.candidate.parentRevisions
            + [submission.validatedStateRevision]
        )
        var manifests: [
          DesignRevisionReference: DesignRevisionManifestModel
        ] = [:]
        for revision in requiredRevisions.sorted(by: {
          $0.revisionID.description < $1.revisionID.description
        }) {
          guard let lifecycle = try await transaction.fetch(
            DesignRevisionLifecycleModel.self,
            identifiedBy: revision.revisionID.description,
            consistency: .serializable
          ), let manifest = try await transaction.fetch(
            DesignRevisionManifestModel.self,
            identifiedBy: revision.revisionID.description,
            consistency: .serializable
          ) else {
            throw DesignDatabaseRuntimeError.revisionNotFound(
              revision.revisionID.description
            )
          }
          try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
            lifecycle,
            revision: revision,
            using: digester
          )
          manifests[revision] = manifest
        }
        guard let validatedManifest = manifests[
          submission.validatedStateRevision
        ] else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A validated merge state has no exact manifest."
          )
        }
        let validatedDescriptor = try await Self.snapshotDescriptor(
          from: validatedManifest,
          revision: submission.validatedStateRevision,
          expectedDatabaseID: databaseID,
          expectedSchemaDigest: self.designSchemaBundleDigest,
          designSchemaBundle: self.designSchemaBundle,
          transaction: transaction,
          digester: digester
        )
        let candidate = submission.candidate
        guard validatedDescriptor.parents.count == 1,
              candidate.parentRevisions.contains(
                validatedDescriptor.parents[0]
              ),
              validatedDescriptor.designSchemaBundleDigest
                == candidate.designSchemaBundleDigest,
              validatedDescriptor.dependencyRootDigest
                == candidate.dependencyRootDigest,
              validatedDescriptor.semanticDependencyGraphDigest
                == candidate.semanticDependencyGraphDigest,
              validatedDescriptor.facetRoots == candidate.facetRoots else {
          let rejection = try Self.disjointMergeRejection(
            operation: operation,
            submission: submission,
            candidateDigest: candidateDigest,
            reason: .validatedStateMismatch,
            using: digester
          )
          try await Self.saveDisjointMergeOutcome(
            .rejected(rejection),
            operation: operation,
            requestDigest: submission.requestDigest,
            transaction: transaction,
            using: digester
          )
          return .rejected(rejection)
        }
        if let existingCandidate = try await transaction.fetch(
          DesignRevisionManifestModel.self,
          identifiedBy: candidateRevision.revisionID.description,
          consistency: .serializable
        ) {
          guard existingCandidate.databaseID == databaseID.description else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A disjoint-merge candidate identity crossed a database boundary."
            )
          }
          let rejection = try Self.disjointMergeRejection(
            operation: operation,
            submission: submission,
            candidateDigest: candidateDigest,
            reason: .candidateRevisionCollision(candidateRevision),
            using: digester
          )
          try await Self.saveDisjointMergeOutcome(
            .rejected(rejection),
            operation: operation,
            requestDigest: submission.requestDigest,
            transaction: transaction,
            using: digester
          )
          return .rejected(rejection)
        }

        let sourceProjectionState = try await
          DesignDatabaseRuntimeProjectionDirectory.load(
            revision: submission.validatedStateRevision,
            databaseID: databaseID,
            count: validatedManifest.projectionDescriptorCount,
            encoded: validatedManifest.projectionDescriptorDigests,
            transaction: transaction,
            digester: digester
          )
        guard let projectionCount = UInt64(
          exactly: sourceProjectionState.materializations.count
        ), projectionCount <= submission.budget.maximumProjectionCount else {
          throw DesignDatabaseRuntimeError
            .collectionRootAuditBudgetExceeded(
              kind: "merge projection count",
              limit: submission.budget.maximumProjectionCount,
              requested: UInt64(
                sourceProjectionState.materializations.count
              )
            )
        }
        let inheritedTrees = sourceProjectionState.materializations.values
          .map { $0.inheritedTree() }
          .sorted { $0.descriptor.family < $1.descriptor.family }
        let inheritedModels = try inheritedTrees.map {
          try $0.models(databaseID: databaseID, revision: candidateRevision)
        }
        guard let sourceDirectoryModel = try await transaction.fetch(
          DesignRevisionPhysicalIdentityDirectoryModel.self,
          identifiedBy: submission.validatedStateRevision.revisionID.description,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A validated merge state has no physical identity directory."
          )
        }
        let sourceDirectory = try
          DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
            model: sourceDirectoryModel,
            revision: submission.validatedStateRevision,
            using: digester
          )
        let metadataStorageTypes = Set([
          DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionDescriptorStorageType,
          DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionBindingStorageType,
          DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionMaterializationStorageType,
        ])
        var candidatePhysicalIdentities = sourceDirectory.identities.filter {
          !metadataStorageTypes.contains($0.storageType)
        }
        for models in inheritedModels {
          candidatePhysicalIdentities.append(
            try DesignDatabaseRuntimePhysicalCollectionClaim
              .projectionDescriptorIdentity(models.descriptor)
          )
          candidatePhysicalIdentities.append(
            try DesignDatabaseRuntimePhysicalCollectionClaim
              .projectionBindingIdentity(models.binding)
          )
          candidatePhysicalIdentities.append(
            try DesignDatabaseRuntimePhysicalCollectionClaim
              .projectionMaterializationIdentity(models.materialization)
          )
        }
        guard let physicalIdentityCount = UInt64(
          exactly: candidatePhysicalIdentities.count
        ), physicalIdentityCount
          <= submission.budget.maximumPhysicalIdentityCount else {
          throw DesignDatabaseRuntimeError
            .collectionRootAuditBudgetExceeded(
              kind: "merge physical identity count",
              limit: submission.budget.maximumPhysicalIdentityCount,
              requested: UInt64(candidatePhysicalIdentities.count)
            )
        }
        for identity in candidatePhysicalIdentities {
          try await DesignDatabaseRuntimePhysicalCollectionClaim
            .requireUnclaimed(
              identity,
              transaction: transaction,
              using: digester
            )
        }
        let candidatePhysicalDirectory = try
          DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
            revision: candidateRevision,
            identities: candidatePhysicalIdentities,
            using: digester
          )
        let changeSetDigest: ContentDigest
        let outcomeDigest: ContentDigest
        do {
          changeSetDigest = try DesignDisjointMergePublicationDigest.changeSet(
            candidate: candidate,
            validatedStateRevision: submission.validatedStateRevision,
            validatedStateCommitOperation:
              authenticatedValidatedCommitReceipt.operation,
            validatedStateCommitRequestDigest:
              authenticatedValidatedCommitReceipt.requestDigest,
            validatedStatePlanDigest:
              authenticatedValidatedCommitReceipt.planDigest,
            stateDigest: validatedDescriptor.stateDigest,
            using: digester
          )
          outcomeDigest = try DesignDisjointMergePublicationDigest
            .publishedOutcome(
              operation: operation,
              requestDigest: submission.requestDigest,
              candidateDigest: candidateDigest,
              candidateRevision: candidateRevision,
              validatedStateRevision: submission.validatedStateRevision,
              validatedStateCommitOperation:
                authenticatedValidatedCommitReceipt.operation,
              validatedStateCommitRequestDigest:
                authenticatedValidatedCommitReceipt.requestDigest,
              validatedStatePlanDigest:
                authenticatedValidatedCommitReceipt.planDigest,
              stateDigest: validatedDescriptor.stateDigest,
              changeSetDigest: changeSetDigest,
              using: digester
            )
        } catch {
          throw DesignDatabaseRuntimeError.commitTransactionFailed(
            reason: String(describing: error)
          )
        }
        let receipt = DesignDisjointMergePublicationReceipt(
          operation: operation,
          requestDigest: submission.requestDigest,
          candidateDigest: candidateDigest,
          baseRevision: candidate.baseRevision,
          parentRevisions: candidate.parentRevisions,
          validatedStateRevision: submission.validatedStateRevision,
          validatedStateCommitOperation:
            authenticatedValidatedCommitReceipt.operation,
          validatedStateCommitRequestDigest:
            authenticatedValidatedCommitReceipt.requestDigest,
          validatedStatePlanDigest:
            authenticatedValidatedCommitReceipt.planDigest,
          candidateRevision: candidateRevision,
          stateDigest: validatedDescriptor.stateDigest,
          changeSetDigest: changeSetDigest,
          designSchemaBundleDigest: candidate.designSchemaBundleDigest,
          dependencyRootDigest: candidate.dependencyRootDigest,
          semanticDependencyGraphDigest:
            candidate.semanticDependencyGraphDigest,
          facetRoots: candidate.facetRoots,
          outcomeDigest: outcomeDigest
        )
        let reachability = try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        )
        let updatedReachability = try DesignDatabaseRuntimeReachability
          .advanced(reachability, kind: "disjoint merge publication")
        for models in inheritedModels {
          try await transaction.save(models.descriptor, precondition: .notExists)
          try await transaction.save(models.materialization, precondition: .notExists)
          try await transaction.save(models.binding, precondition: .notExists)
        }
        try await transaction.save(
          candidatePhysicalDirectory.model(),
          precondition: .notExists
        )
        try await transaction.save(
          try Self.disjointMergeRevisionManifest(
            receipt: receipt,
            directDependencyLock: validatedDescriptor.directDependencyLock,
            projectionDirectory: try DesignDatabaseRuntimeProjectionDirectory
              .encode(inheritedTrees)
          ),
          precondition: .notExists
        )
        try await transaction.save(
          try DesignDatabaseRuntimeRevisionLifecycle.makeVisible(
            revision: candidateRevision,
            reachabilityGeneration: updatedReachability.generation,
            using: digester
          ),
          precondition: .notExists
        )
        try await transaction.save(updatedReachability, precondition: .exists)
        try await Self.saveDisjointMergeOutcome(
          .published(receipt),
          operation: operation,
          requestDigest: submission.requestDigest,
          transaction: transaction,
          using: digester
        )
        return .published(receipt)
      }
    } catch DatabaseContextError.commitOutcomeUnknown {
      return .outcomeUnknown(
        DesignDisjointMergePublicationUnknown(
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

  package func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError)
    -> DesignDisjointMergePublicationStatus
  {
    let context = try context()
    do {
      return try await context.withTransaction { transaction in
        let key = DesignDatabaseRuntimeOperationClaim.key(operation)
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        let outcome = try await transaction.fetch(
          DesignDisjointMergeOperationModel.self,
          identifiedBy: key,
          consistency: .serializable
        )
        guard claim != nil || outcome != nil else { return .notRecorded }
        guard let claim, let outcome else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A disjoint-merge claim and outcome are not atomic."
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          claim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.disjointMergeKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError
            .disjointMergeIdempotencyConflict(operation: key)
        }
        switch try Self.disjointMergeResult(
          model: outcome,
          operation: operation,
          requestDigest: requestDigest,
          using: digester
        ) {
        case .published(let receipt): return .published(receipt)
        case .rejected(let rejection): return .rejected(rejection)
        case .outcomeUnknown:
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A persisted disjoint-merge outcome cannot remain unknown."
          )
        }
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private static func authenticatedValidatedCommitReceipt(
    submission: DesignDisjointMergePublicationSubmission,
    expectedReceipt: DesignCommitReceipt,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    transaction: DatabaseTransaction,
    using digester: any ContentDigesting
  ) async throws -> DesignCommitReceipt {
    let validatedSubmission = submission.validatedStateCommit
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: validatedSubmission.operationID
    )
    guard validatedSubmission.operationID != submission.operationID,
          validatedSubmission.plan.databaseID == databaseID,
          submission.candidate.parentRevisions.contains(
            validatedSubmission.plan.baseRevision
          ),
          expectedReceipt.operation == operation,
          expectedReceipt.requestDigest == validatedSubmission.requestDigest,
          expectedReceipt.planDigest == validatedSubmission.plan.planDigest,
          expectedReceipt.baseRevision
            == validatedSubmission.plan.baseRevision,
          expectedReceipt.candidateRevision
            == submission.validatedStateRevision else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A disjoint-merge validation receipt escaped its exact submission scope."
      )
    }

    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    guard let claim = try await transaction.fetch(
      DesignOperationClaimModel.self,
      identifiedBy: key,
      consistency: .serializable
    ), try DesignDatabaseRuntimeOperationClaim.matches(
      claim,
      operation: operation,
      kind: DesignDatabaseRuntimeOperationClaim.commitKind,
      requestDigest: validatedSubmission.requestDigest
    ), let model = try await transaction.fetch(
      DesignCommitOperationModel.self,
      identifiedBy: key,
      consistency: .serializable
    ) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A disjoint-merge validation commit has no exact persisted outcome."
      )
    }
    let result = try maintenanceCommitResult(
      model: model,
      operation: operation,
      requestDigest: validatedSubmission.requestDigest,
      using: digester
    )
    guard case .committed(let persistedReceipt) = result,
          persistedReceipt == expectedReceipt else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A disjoint-merge validation receipt does not match its persisted commit outcome."
      )
    }
    return persistedReceipt
  }
}

private extension DesignDatabaseRuntimeAttachment {
  enum PersistedDisjointMergeOutcome: Codable {
    case published(DesignDisjointMergePublicationReceipt)
    case rejected(DesignDisjointMergePublicationRejection)
  }

  static func disjointMergeCandidateRevision(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionReference {
    guard requestDigest.algorithm == .sha256,
          requestDigest.hexadecimalValue.utf8.count == 64 else {
      throw .commitTransactionFailed(
        reason: "A disjoint-merge request digest must be SHA-256."
      )
    }
    do {
      return DesignRevisionReference(
        databaseID: operation.databaseID,
        revisionID: try DesignRevisionID(
          hexadecimalValue: String(
            requestDigest.hexadecimalValue.prefix(32)
          )
        )
      )
    } catch {
      throw .commitTransactionFailed(
        reason: "A disjoint-merge digest could not form a revision identity."
      )
    }
  }

  static func disjointMergeRejection(
    operation: DesignDatabaseOperationReference,
    submission: DesignDisjointMergePublicationSubmission,
    candidateDigest: ContentDigest,
    reason: DesignDisjointMergePublicationRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDisjointMergePublicationRejection
  {
    do {
      return DesignDisjointMergePublicationRejection(
        operation: operation,
        requestDigest: submission.requestDigest,
        candidateDigest: candidateDigest,
        reason: reason,
        outcomeDigest: try DesignDisjointMergePublicationDigest
          .rejectedOutcome(
            operation: operation,
            requestDigest: submission.requestDigest,
            candidateDigest: candidateDigest,
            reason: reason,
            using: digester
          )
      )
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  static func saveDisjointMergeOutcome(
    _ outcome: PersistedDisjointMergeOutcome,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    transaction: DatabaseTransaction,
    using digester: any ContentDigesting
  ) async throws {
    let data = try JSONEncoder().encode(outcome)
    let payloadDigest = try DesignMutationPlanDigest.payload(
      Array(data),
      using: digester
    )
    var model = DesignDisjointMergeOperationModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    switch outcome {
    case .published: model.outcomeKind = 0
    case .rejected: model.outcomeKind = 1
    }
    model.payload = ByteString(Array(data))
    model.payloadDigestAlgorithm = payloadDigest.algorithm.rawValue
    model.payloadDigestValue = payloadDigest.hexadecimalValue
    try await transaction.save(
      DesignDatabaseRuntimeOperationClaim.make(
        operation: operation,
        kind: DesignDatabaseRuntimeOperationClaim.disjointMergeKind,
        requestDigest: requestDigest
      ),
      precondition: .notExists
    )
    try await transaction.save(model, precondition: .notExists)
  }

  static func disjointMergeResult(
    model: DesignDisjointMergeOperationModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDisjointMergePublicationResult {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue else {
      throw .disjointMergeIdempotencyConflict(operation: model.id)
    }
    do {
      let data = Data(Array(model.payload))
      let payloadDigest = try DesignMutationPlanDigest.payload(
        Array(data),
        using: digester
      )
      guard model.payloadDigestAlgorithm == payloadDigest.algorithm.rawValue,
            model.payloadDigestValue == payloadDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A disjoint-merge outcome payload digest is invalid."
        )
      }
      let outcome = try JSONDecoder().decode(
        PersistedDisjointMergeOutcome.self,
        from: data
      )
      switch outcome {
      case .published(let receipt):
        guard model.outcomeKind == 0,
              receipt.operation == operation,
              receipt.requestDigest == requestDigest,
              receipt.outcomeDigest == (try
                DesignDisjointMergePublicationDigest.publishedOutcome(
                  operation: operation,
                  requestDigest: requestDigest,
                  candidateDigest: receipt.candidateDigest,
                  candidateRevision: receipt.candidateRevision,
                  validatedStateRevision: receipt.validatedStateRevision,
                  validatedStateCommitOperation:
                    receipt.validatedStateCommitOperation,
                  validatedStateCommitRequestDigest:
                    receipt.validatedStateCommitRequestDigest,
                  validatedStatePlanDigest: receipt.validatedStatePlanDigest,
                  stateDigest: receipt.stateDigest,
                  changeSetDigest: receipt.changeSetDigest,
                  using: digester
                )) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A published disjoint-merge outcome is inconsistent."
          )
        }
        return .published(receipt)
      case .rejected(let rejection):
        guard model.outcomeKind == 1,
              rejection.operation == operation,
              rejection.requestDigest == requestDigest,
              rejection.outcomeDigest == (try
                DesignDisjointMergePublicationDigest.rejectedOutcome(
                  operation: operation,
                  requestDigest: requestDigest,
                  candidateDigest: rejection.candidateDigest,
                  reason: rejection.reason,
                  using: digester
                )) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A rejected disjoint-merge outcome is inconsistent."
          )
        }
        return .rejected(rejection)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A disjoint-merge outcome could not be decoded: \(error)"
      )
    }
  }

  static func disjointMergeRevisionManifest(
    receipt: DesignDisjointMergePublicationReceipt,
    directDependencyLock: DesignDependencyLock,
    projectionDirectory: String
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionManifestModel {
    guard receipt.parentRevisions.count == 2 else {
      throw .persistedStateCorrupt(
        reason: "A disjoint-merge receipt does not contain two parents."
      )
    }
    var model = DesignRevisionManifestModel()
    model.id = receipt.candidateRevision.revisionID.description
    model.databaseID = receipt.candidateRevision.databaseID.description
    model.parentCount = 2
    model.parentRevisionIDs = receipt.parentRevisions
      .map(\.revisionID.description)
      .joined(separator: "\n")
    model.stateDigestAlgorithm = receipt.stateDigest.algorithm.rawValue
    model.stateDigestValue = receipt.stateDigest.hexadecimalValue
    model.schemaRootDigestAlgorithm = receipt
      .designSchemaBundleDigest.algorithm.rawValue
    model.schemaRootDigestValue = receipt
      .designSchemaBundleDigest.hexadecimalValue
    model.dependencyRootDigestAlgorithm = receipt
      .dependencyRootDigest.algorithm.rawValue
    model.dependencyRootDigestValue = receipt
      .dependencyRootDigest.hexadecimalValue
    model.dependencyLockEntryCount = Int64(directDependencyLock.entries.count)
    model.dependencyLockEntries = try
      DesignDatabaseRuntimeDependencyLockDirectory.encode(
        directDependencyLock
      )
    model.dependencyGraphDigestAlgorithm = receipt
      .semanticDependencyGraphDigest.algorithm.rawValue
    model.dependencyGraphDigestValue = receipt
      .semanticDependencyGraphDigest.hexadecimalValue
    model.facetRootCount = Int64(receipt.facetRoots.count)
    model.facetRoots = try DesignDatabaseRuntimeFacetRootDirectory.encode(
      receipt.facetRoots
    )
    model.projectionDescriptorCount = Int64(
      projectionDirectory.isEmpty
        ? 0
        : projectionDirectory.split(separator: "\n").count
    )
    model.projectionDescriptorDigests = projectionDirectory
    model.directChangeRootDigestAlgorithm = receipt
      .changeSetDigest.algorithm.rawValue
    model.directChangeRootDigestValue = receipt
      .changeSetDigest.hexadecimalValue
    return model
  }
}
