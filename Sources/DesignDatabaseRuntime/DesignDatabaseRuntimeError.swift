import CircuiteFoundation

public enum DesignDatabaseRuntimeError: Error, Sendable, Equatable {
  case invalidContributionIdentifier(String)
  case emptyContribution(DesignDatabaseRuntimeContributionID)
  case duplicateContribution(DesignDatabaseRuntimeContributionID)
  case duplicateDesignSchema(DesignSchemaID)
  case duplicateEntity(name: String)
  case contributionEntityRuntimeMismatch(
    contribution: DesignDatabaseRuntimeContributionID,
    entityNames: [String],
    runtimeEntityNames: [String]
  )
  case mutationAdapterBindingMismatch(
    contribution: DesignDatabaseRuntimeContributionID
  )
  case duplicateMutationAdapter(DesignSchemaID)
  case invalidPhysicalWriteReclaimer(storageType: String)
  case duplicatePhysicalWriteReclaimer(storageType: String)
  case physicalWriteReclaimerUnavailable(storageType: String)
  case physicalWriteReclaimFailed(identity: String, reason: String)
  case schemaConstructionFailed(reason: String)
  case frameworkConfigurationFailed(reason: String)
  case registrationDigestFailed(reason: String)
  case containerProviderFailed(reason: String)
  case containerSchemaMismatch(expected: String, actual: String)
  case genesisRequestBindingMismatch(reason: String)
  case databaseNotFound
  case databaseIdentityMismatch(expected: String, actual: String)
  case runtimeRegistrationMismatch(expected: String, actual: String)
  case missingFeatureCapability(String)
  case incompatibleFeatureCapability(String)
  case databaseAlreadyExists(existingDatabaseID: String)
  case creationIdempotencyConflict(operation: String)
  case creationTransactionFailed(reason: String)
  case referenceIdempotencyConflict(operation: String)
  case referenceTransactionFailed(reason: String)
  case generationExhausted(kind: String)
  case namedReferenceNotFound(String)
  case revisionNotFound(String)
  case revisionDeleting(String)
  case revisionCollected(String)
  case retentionTransactionFailed(reason: String)
  case commitAbandonmentIdempotencyConflict(operation: String)
  case commitAbandonmentTransactionFailed(reason: String)
  case commitIdempotencyConflict(operation: String)
  case disjointMergeIdempotencyConflict(operation: String)
  case commitStagingConflict(operation: String)
  case validatedMutationDirectoryBudgetExceeded(limit: UInt64, requested: UInt64)
  case preparedMutationDirectoryBudgetExceeded(limit: UInt64, requested: UInt64)
  case stagingPhysicalIdentityDirectoryBudgetExceeded(
    kind: String,
    limit: UInt64,
    requested: UInt64
  )
  case commitSubmissionCapsuleBudgetExceeded(limit: UInt64, requested: UInt64)
  case commitRecoveryIntentBudgetExceeded(limit: UInt64, requested: UInt64)
  case deletionCandidateBudgetExceeded(limit: UInt64, requested: UInt64)
  case collectionRecoveryIntentBudgetExceeded(limit: UInt64, requested: UInt64)
  case collectionRootAuditBudgetExceeded(
    kind: String,
    limit: UInt64,
    requested: UInt64
  )
  case collectionReachabilityChanged(expected: Int64, actual: Int64)
  case revisionStillReachable(revisionID: String, rootKind: String)
  case collectionIdempotencyConflict(operation: String)
  case physicalIdentityDirectoryNotFound(revisionID: String)
  case physicalWriteDeleting(identity: String, collectionOperation: String)
  case commitTransactionFailed(reason: String)
  case persistedStateCorrupt(reason: String)
  case attachmentClosed
}
