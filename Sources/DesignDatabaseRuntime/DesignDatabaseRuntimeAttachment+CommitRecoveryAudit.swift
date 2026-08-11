import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func validateCommitRecoveryBeforeServingOpens(
    maximumIntentCount: UInt64 = 4_096,
    scanPageSize: Int = 128,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) {
    guard maximumIntentCount > 0, scanPageSize > 0 else {
      throw .commitRecoveryIntentBudgetExceeded(
        limit: maximumIntentCount,
        requested: maximumIntentCount == 0 ? 1 : 0
      )
    }
    let databaseContext = try context()
    var continuation: DatabaseScanContinuation?
    var observedCount: UInt64 = 0
    repeat {
      let pageContinuation = continuation
      let page: DesignDatabaseRuntimeReadPage<DesignCommitBuildIntentModel>
      do {
        page = try await databaseContext.withTransaction { transaction in
          let scanned = try await transaction.scan(
            DesignCommitBuildIntentModel.self,
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
        throw .commitRecoveryIntentBudgetExceeded(
          limit: maximumIntentCount,
          requested: UInt64.max
        )
      }
      let (nextCount, overflow) = observedCount.addingReportingOverflow(
        pageCount
      )
      guard !overflow, nextCount <= maximumIntentCount else {
        throw .commitRecoveryIntentBudgetExceeded(
          limit: maximumIntentCount,
          requested: overflow ? UInt64.max : nextCount
        )
      }
      observedCount = nextCount
      for intent in page.items {
        try await validateRecoverableCommitIntent(intent, using: digester)
      }
      continuation = page.continuation
    } while continuation != nil
  }

  private func validateRecoverableCommitIntent(
    _ intent: DesignCommitBuildIntentModel,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let operation: DesignDatabaseOperationReference
    let requestDigest: ContentDigest
    do {
      operation = DesignDatabaseOperationReference(
        databaseID: try DesignDatabaseID(
          hexadecimalValue: intent.databaseID
        ),
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: intent.subjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(
          rawValue: intent.operationID
        )
      )
      requestDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: intent.requestDigestAlgorithm
        ),
        hexadecimalValue: intent.requestDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit recovery intent identity is malformed."
      )
    }
    guard intent.id == DesignDatabaseRuntimeOperationClaim.key(operation) else {
      throw .persistedStateCorrupt(
        reason: "A commit recovery intent does not match its scoped operation key."
      )
    }
    guard let submission = try await persistedCommitSubmission(
      operation: operation,
      requestDigest: requestDigest,
      digester: digester
    ) else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has no recoverable exact submission."
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
      throw .persistedStateCorrupt(
        reason: "A commit recovery candidate revision is malformed."
      )
    }
    _ = try DesignDatabaseRuntimeCommitBuildIntent.validateStored(
      intent,
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      using: digester
    )
    let databaseContext = try context()
    let recoveryState: (
      DesignStagingRootModel?,
      DesignStagingPhysicalIdentityDirectoryModel?
    )
    do {
      recoveryState = try await databaseContext.withTransaction { transaction in
        let stagingRoot = try await transaction.fetch(
          DesignStagingRootModel.self,
          identifiedBy: intent.id,
          consistency: .serializable
        )
        let physicalIdentityDirectory = try await transaction.fetch(
          DesignStagingPhysicalIdentityDirectoryModel.self,
          identifiedBy: intent.id,
          consistency: .serializable
        )
        return (stagingRoot, physicalIdentityDirectory)
      }
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard let stagingRoot = recoveryState.0,
          let physicalIdentityDirectoryModel = recoveryState.1 else {
      throw .persistedStateCorrupt(
        reason: "A commit recovery intent has no durable staging root and physical identity directory."
      )
    }
    let stagingDigest: ContentDigest
    do {
      stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: intent.stagingDigestAlgorithm
        ),
        hexadecimalValue: intent.stagingDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit recovery staging digest is malformed."
      )
    }
    try DesignDatabaseRuntimeStagingRoot.validate(
      stagingRoot,
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      stagingDigest: stagingDigest,
      using: digester
    )
    let physicalIdentityDirectory = try
      DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
        model: physicalIdentityDirectoryModel,
        operation: operation,
        submission: submission,
        candidateRevision: candidateRevision,
        using: digester
      )
    guard try DesignDatabaseRuntimeStagingRoot
      .physicalIdentityDirectoryDigest(stagingRoot)
        == physicalIdentityDirectory.digest else {
      throw .persistedStateCorrupt(
        reason: "A recovered staging root does not bind its physical identity directory."
      )
    }
  }
}
