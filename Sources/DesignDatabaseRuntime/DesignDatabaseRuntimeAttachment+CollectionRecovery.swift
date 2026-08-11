import CircuiteFoundation
import CircuiteFoundationCrypto
import Database

extension DesignDatabaseRuntimeAttachment {
  package func restoreCollectionAdmissionsBeforeServingOpens(
    maximumIntentCount: UInt64 = 4_096,
    maximumRevisionCountPerIntent: UInt64 = 256,
    maximumPhysicalIdentityCountPerIntent: UInt64 = 256,
    scanPageSize: Int = 128,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) {
    guard maximumIntentCount > 0,
          maximumRevisionCountPerIntent > 0,
          maximumPhysicalIdentityCountPerIntent > 0,
          scanPageSize > 0 else {
      throw .collectionRecoveryIntentBudgetExceeded(
        limit: maximumIntentCount,
        requested: maximumIntentCount == 0 ? 1 : 0
      )
    }
    let databaseContext = try context()
    var continuation: DatabaseScanContinuation?
    var observedCount: UInt64 = 0
    repeat {
      let pageContinuation = continuation
      let page: DesignDatabaseRuntimeReadPage<DesignCollectionIntentModel>
      do {
        page = try await databaseContext.withTransaction { transaction in
          let scanned = try await transaction.scan(
            DesignCollectionIntentModel.self,
            after: pageContinuation,
            limit: scanPageSize
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
        throw .collectionRecoveryIntentBudgetExceeded(
          limit: maximumIntentCount,
          requested: UInt64.max
        )
      }
      let (nextCount, overflow) = observedCount.addingReportingOverflow(
        pageCount
      )
      guard !overflow, nextCount <= maximumIntentCount else {
        throw .collectionRecoveryIntentBudgetExceeded(
          limit: maximumIntentCount,
          requested: overflow ? UInt64.max : nextCount
        )
      }
      observedCount = nextCount
      for intent in page.items {
        try await restoreCollectionAdmission(
          intent,
          maximumRevisionCount: maximumRevisionCountPerIntent,
          maximumPhysicalIdentityCount: maximumPhysicalIdentityCountPerIntent,
          using: digester
        )
      }
      continuation = page.continuation
    } while continuation != nil
  }

  package func restoreCollectionAdmission(
    _ intent: DesignCollectionIntentModel,
    maximumRevisionCount: UInt64,
    maximumPhysicalIdentityCount: UInt64 = 256,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
      intent,
      maximumRevisionCount: maximumRevisionCount,
      using: digester
    )
    let databaseContext = try context()
    let persisted: (
      DesignOperationClaimModel?,
      DesignCollectionPhysicalIdentityDirectoryModel?,
      DesignReachabilityStateModel,
      [DesignRevisionLifecycleModel]
    )
    do {
      persisted = try await databaseContext.withTransaction { transaction in
        let claim = try await transaction.fetch(
          DesignOperationClaimModel.self,
          identifiedBy: intent.id,
          consistency: .serializable
        )
        let reachability = try await DesignDatabaseRuntimeReachability.require(
          databaseID: recovered.operation.databaseID,
          transaction: transaction
        )
        let physicalIdentityDirectory = try await transaction.fetch(
          DesignCollectionPhysicalIdentityDirectoryModel.self,
          identifiedBy: intent.id,
          consistency: .serializable
        )
        let lifecycles = try await transaction.fetch(
          DesignRevisionLifecycleModel.self,
          identifiedBy: recovered.candidates.revisions.map(
            \.revisionID.description
          ),
          consistency: .serializable
        )
        return (claim, physicalIdentityDirectory, reachability, lifecycles)
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard let claim = persisted.0,
          let physicalIdentityDirectoryModel = persisted.1,
          try DesignDatabaseRuntimeOperationClaim.matches(
            claim,
            operation: recovered.operation,
            kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
            requestDigest: recovered.requestDigest
          ),
          persisted.2.generation >= intent.admittedReachabilityGeneration,
          persisted.3.count == recovered.candidates.revisions.count else {
      throw .persistedStateCorrupt(
        reason: "A collection intent is missing its claim, reachability, or lifecycle binding."
      )
    }
    let physicalIdentityDirectory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        model: physicalIdentityDirectoryModel,
        operation: recovered.operation,
        requestDigest: recovered.requestDigest,
        maximumIdentityCount: maximumPhysicalIdentityCount,
        using: digester
      )
    guard recovered.physicalIdentityDirectoryDigest
            == physicalIdentityDirectory.digest,
          recovered.physicalIdentityCount
            == UInt64(physicalIdentityDirectory.identities.count) else {
      throw .persistedStateCorrupt(
        reason: "A recovered collection intent does not bind its physical identity directory."
      )
    }
    try await validateRejectedStagingRootStates(
      directory: physicalIdentityDirectory,
      collectionState: recovered.state,
      databaseID: recovered.operation.databaseID,
      context: databaseContext,
      using: digester
    )
    let physicalClaimStates: [
      DesignDatabaseRuntimePhysicalCollectionClaimState
    ]
    if recovered.state == .collected {
      physicalClaimStates = []
    } else {
      physicalClaimStates = try await
        DesignDatabaseRuntimeCollectionPhysicalClaimValidator.validate(
          directory: physicalIdentityDirectory,
          collectionIntentID: intent.id,
          context: databaseContext,
          using: digester
        )
    }
    switch recovered.state {
    case .admitted:
      guard intent.deletedPhysicalIdentityCount == 0,
            physicalClaimStates.allSatisfy({ $0 == .claimed }) else {
        throw .persistedStateCorrupt(
          reason: "An admitted collection has already deleted a physical claim."
        )
      }
    case .sweeping:
      guard let deletedCount = Int(
        exactly: intent.deletedPhysicalIdentityCount
      ), physicalClaimStates.indices.allSatisfy({ index in
        physicalClaimStates[index] == (index < deletedCount ? .deleted : .claimed)
      }) else {
        throw .persistedStateCorrupt(
          reason: "A sweeping collection claim prefix does not match its persisted progress."
        )
      }
    case .collected:
      guard intent.deletedPhysicalIdentityCount
              == intent.physicalIdentityCount else {
        throw .persistedStateCorrupt(
          reason: "A collected operation has incomplete terminal progress."
        )
      }
    }
    for revision in recovered.candidates.revisions {
      guard let lifecycle = persisted.3.first(
        where: { $0.revisionID == revision.revisionID.description }
      ) else {
        throw .persistedStateCorrupt(
          reason: "A collection intent candidate has no lifecycle record."
        )
      }
      let lifecycleState = try DesignDatabaseRuntimeRevisionLifecycle.validate(
        lifecycle,
        revision: revision,
        using: digester
      )
      switch recovered.state {
      case .admitted, .sweeping:
        guard lifecycleState == .deleting else {
          throw .persistedStateCorrupt(
            reason: "A nonterminal collection intent has no deleting lifecycle fence."
          )
        }
      case .collected:
        guard lifecycleState == .collected else {
          throw .persistedStateCorrupt(
            reason: "A terminal collection intent has no collected lifecycle tombstone."
          )
        }
      }
    }
    if recovered.state != .collected {
      _ = try await snapshotLeaseCoordinator.admitDeletion(
        identifier: intent.id,
        candidates: recovered.candidates
      )
    }
  }
}
