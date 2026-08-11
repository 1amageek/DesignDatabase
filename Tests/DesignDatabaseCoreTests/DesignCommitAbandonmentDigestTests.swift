import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Testing

@Suite
struct DesignCommitAbandonmentDigestTests {
  @Test
  func requestAndOutcomeDigestsBindExactMaintenanceLineage() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 3, low: 4)
    let targetOperation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: try DesignDatabaseOperationID(rawValue: "target")
    )
    let operationID = try DesignDatabaseOperationID(rawValue: "abandon")
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: operationID
    )
    let targetRequestDigest = try digest(repeating: "a")
    let evidenceDigest = try digest(repeating: "b")
    let otherEvidenceDigest = try digest(repeating: "c")
    let targetOutcomeDigest = try digest(repeating: "d")
    let reason = try DesignCommitAbandonmentReason(rawValue: "caller-abandoned")
    let digester = SHA256ContentDigester()

    let requestDigest = try DesignCommitAbandonmentDigest.request(
      operationID: operationID,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      using: digester
    )
    let replayedRequestDigest = try DesignCommitAbandonmentDigest.request(
      operationID: operationID,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      using: digester
    )
    #expect(requestDigest == replayedRequestDigest)
    let otherRequestDigest = try DesignCommitAbandonmentDigest.request(
      operationID: operationID,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: otherEvidenceDigest,
      using: digester
    )
    #expect(requestDigest != otherRequestDigest)

    let abandonedOutcome = try DesignCommitAbandonmentDigest.abandonedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      targetCommitOutcomeDigest: targetOutcomeDigest,
      stagingRootTerminalized: true,
      reachabilityGeneration: 2,
      using: digester
    )
    let preIntentOutcome = try DesignCommitAbandonmentDigest.abandonedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      targetCommitOutcomeDigest: targetOutcomeDigest,
      stagingRootTerminalized: false,
      reachabilityGeneration: 2,
      using: digester
    )
    #expect(abandonedOutcome != preIntentOutcome)
    let notRecordedOutcome = try DesignCommitAbandonmentDigest.rejectedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      abandonmentReason: reason,
      evidenceDigest: evidenceDigest,
      reason: .targetNotRecorded,
      using: digester
    )
    let alreadyRejectedOutcome = try DesignCommitAbandonmentDigest.rejectedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      abandonmentReason: reason,
      evidenceDigest: evidenceDigest,
      reason: .targetAlreadyRejected(outcomeDigest: targetOutcomeDigest),
      using: digester
    )
    #expect(notRecordedOutcome != alreadyRejectedOutcome)
  }

  private func digest(repeating byte: String) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: byte, count: 64)
    )
  }
}
