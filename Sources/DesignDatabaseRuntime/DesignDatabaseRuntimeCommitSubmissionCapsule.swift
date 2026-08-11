import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import Foundation

package struct DesignDatabaseRuntimeCommitSubmissionCapsule: Sendable {
  package static let maximumEncodedByteCount: UInt64 = 67_108_864

  package let submission: DesignCommitSubmission
  package let encodedPayload: [UInt8]
  package let digest: ContentDigest

  package init(
    submission: DesignCommitSubmission,
    operation: DesignDatabaseOperationReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    try Self.validate(
      submission,
      operation: operation,
      expectedRequestDigest: submission.requestDigest,
      expectedPlanDigest: submission.plan.planDigest,
      using: digester
    )
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(submission)
      guard let byteCount = UInt64(exactly: data.count),
            byteCount <= Self.maximumEncodedByteCount else {
        throw DesignDatabaseRuntimeError.commitSubmissionCapsuleBudgetExceeded(
          limit: Self.maximumEncodedByteCount,
          requested: UInt64(exactly: data.count) ?? UInt64.max
        )
      }
      let bytes = Array(data)
      self.submission = submission
      self.encodedPayload = bytes
      self.digest = try Self.digest(bytes, using: digester)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: "The commit submission capsule could not be encoded: \(error)"
      )
    }
  }

  package init(
    model: DesignCommitSubmissionModel,
    operation: DesignDatabaseOperationReference,
    expectedRequestDigest: ContentDigest,
    expectedPlanDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm
            == expectedRequestDigest.algorithm.rawValue,
          model.requestDigestValue
            == expectedRequestDigest.hexadecimalValue,
          model.planDigestAlgorithm == expectedPlanDigest.algorithm.rawValue,
          model.planDigestValue == expectedPlanDigest.hexadecimalValue else {
      throw .commitIdempotencyConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    let bytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: bytes.count),
          byteCount <= Self.maximumEncodedByteCount else {
      throw .persistedStateCorrupt(
        reason: "A commit submission capsule exceeds the Runtime byte limit."
      )
    }
    do {
      let observedDigest = try Self.digest(bytes, using: digester)
      guard model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A commit submission capsule digest does not match its payload."
        )
      }
      let submission = try JSONDecoder().decode(
        DesignCommitSubmission.self,
        from: Data(bytes)
      )
      try Self.validate(
        submission,
        operation: operation,
        expectedRequestDigest: expectedRequestDigest,
        expectedPlanDigest: expectedPlanDigest,
        using: digester
      )
      self.submission = submission
      self.encodedPayload = bytes
      self.digest = observedDigest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit submission capsule could not be decoded: \(error)"
      )
    }
  }

  package func model(
    operation: DesignDatabaseOperationReference
  ) -> DesignCommitSubmissionModel {
    var model = DesignCommitSubmissionModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
    model.requestDigestValue = submission.requestDigest.hexadecimalValue
    model.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
    model.planDigestValue = submission.plan.planDigest.hexadecimalValue
    model.payload = ByteString(encodedPayload)
    model.payloadDigestAlgorithm = digest.algorithm.rawValue
    model.payloadDigestValue = digest.hexadecimalValue
    return model
  }

  private static func validate(
    _ submission: DesignCommitSubmission,
    operation: DesignDatabaseOperationReference,
    expectedRequestDigest: ContentDigest,
    expectedPlanDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard submission.operationID == operation.operationID,
          submission.plan.databaseID == operation.databaseID,
          submission.plan.baseRevision.databaseID == operation.databaseID,
          submission.plan.schemaVersion == DesignMutationPlan.currentSchemaVersion,
          submission.requestDigest == expectedRequestDigest,
          submission.plan.planDigest == expectedPlanDigest else {
      throw .commitIdempotencyConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    do {
      for segment in submission.plan.segments {
        let payloadDigest = try DesignMutationPlanDigest.payload(
          segment.payload,
          using: digester
        )
        guard payloadDigest == segment.payloadDigest else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit submission capsule contains a segment payload digest mismatch."
          )
        }
      }
      if let dependencyUpdate = submission.plan.dependencyLockUpdate {
        let dependencyRoot = try DesignDependencyLockDigest.root(
          dependencyUpdate.replacement,
          using: digester
        )
        guard dependencyRoot == dependencyUpdate.dependencyRootDigest else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A commit submission capsule contains a dependency-lock root mismatch."
          )
        }
      }
      let planDigest = try DesignMutationPlanDigest.plan(
        databaseID: submission.plan.databaseID,
        baseRevision: submission.plan.baseRevision,
        designSchemaBundleDigest: submission.plan.designSchemaBundleDigest,
        dependencyRootDigest: submission.plan.dependencyRootDigest,
        semanticDependencyGraphDigest: submission.plan
          .semanticDependencyGraphDigest,
        sourceEvidenceDigest: submission.plan.sourceEvidenceDigest,
        budget: submission.plan.budget,
        segments: submission.plan.segments,
        dependencyLockUpdate: submission.plan.dependencyLockUpdate,
        using: digester
      )
      guard planDigest == submission.plan.planDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A commit submission capsule has a noncanonical plan digest."
        )
      }
      let requestDigest = try DesignMutationPlanDigest.request(
        operationID: submission.operationID,
        planDigest: submission.plan.planDigest,
        using: digester
      )
      guard requestDigest == submission.requestDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A commit submission capsule has a noncanonical request digest."
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit submission capsule request digest could not be verified: \(error)"
      )
    }
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws -> ContentDigest {
    let byteCount = UInt64(bytes.count)
    let limits = try ContentDigestSessionLimits(
      maximumChunkByteCount: max(byteCount, 1),
      maximumTotalByteCount: max(byteCount, 1),
      maximumUpdateCount: 1
    )
    return try digester.digest(
      using: .sha256,
      limits: limits
    ) { (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
      try lease.update(bytes)
    }.digest
  }
}
