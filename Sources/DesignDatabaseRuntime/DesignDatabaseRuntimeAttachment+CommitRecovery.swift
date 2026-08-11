import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

extension DesignDatabaseRuntimeAttachment {
  package func persistedCommitSubmission(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) async throws(DesignDatabaseRuntimeError) -> DesignCommitSubmission? {
    let databaseContext = try context()
    let key = DesignDatabaseRuntimeOperationClaim.key(operation)
    do {
      return try await databaseContext.withTransaction { transaction in
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
        let model = try await transaction.fetch(
          DesignCommitSubmissionModel.self,
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
        guard claim != nil || outcome != nil || model != nil
          || reservation != nil || validatedDirectory != nil else {
          return nil
        }
        guard let claim else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit recovery record exists without its operation claim."
          )
        }
        guard try DesignDatabaseRuntimeOperationClaim.matches(
          claim,
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.commitKind,
          requestDigest: requestDigest
        ) else {
          throw DesignDatabaseRuntimeError.commitIdempotencyConflict(
            operation: key
          )
        }
        switch (model, reservation, validatedDirectory) {
        case (nil, nil, nil):
          guard outcome != nil else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A nonterminal commit claim has no exact submission capsule."
            )
          }
          return nil
        case (
          .some(let model),
          .some(let reservation),
          .some(let validatedDirectory)
        ):
          let planDigest = try Self.recoveryDigest(
            algorithm: reservation.planDigestAlgorithm,
            value: reservation.planDigestValue,
            field: "plan"
          )
          let validatedDigest = try Self.recoveryDigest(
            algorithm: reservation.validatedDirectoryDigestAlgorithm,
            value: reservation.validatedDirectoryDigestValue,
            field: "validated mutation directory"
          )
          try Self.validateIdentityReservationStatus(
            reservation,
            operation: operation,
            requestDigest: requestDigest,
            validatedDirectoryDigest: validatedDigest,
            validatedMutationCount: reservation.validatedMutationCount
          )
          try DesignDatabaseRuntimeValidatedMutationDirectory.validateStatus(
            validatedDirectory,
            operation: operation,
            requestDigest: requestDigest,
            expectedDigest: validatedDigest,
            expectedRecordCount: reservation.validatedMutationCount,
            using: digester
          )
          return try DesignDatabaseRuntimeCommitSubmissionCapsule(
            model: model,
            operation: operation,
            expectedRequestDigest: requestDigest,
            expectedPlanDigest: planDigest,
            using: digester
          ).submission
        default:
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit submission, validated mutation directory, and identity reservation are not atomic."
          )
        }
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private static func recoveryDigest(
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
        reason: "A commit recovery \(field) digest is malformed."
      )
    }
  }
}
