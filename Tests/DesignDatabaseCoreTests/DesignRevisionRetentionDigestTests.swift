import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Testing

@Suite
struct DesignRevisionRetentionDigestTests {
  @Test
  func canonicalVersionOneGoldenVectorsRemainStable() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 3, low: 4)
    )
    let operationID = try DesignDatabaseOperationID(rawValue: "retain-1")
    let claimID = try DesignRevisionRetentionID(rawValue: "claim-1")
    let evidenceDigest = try digest(repeating: "aa")
    let requestDigest = try digest(repeating: "bb")
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
        high: 5,
        low: 6
      ),
      operationID: operationID
    )
    let digester = SHA256ContentDigester()

    #expect(DesignRevisionRetentionDigest.canonicalVersion == 1)
    #expect(
      try DesignRevisionRetentionDigest.retainingRequest(
        operationID: operationID,
        claimID: claimID,
        revision: revision,
        reason: DesignRevisionRetentionReason(rawValue: "release"),
        evidenceDigest: evidenceDigest,
        using: digester
      ).hexadecimalValue
        == "701a4701bf7a2a11fd35732003fc5ba9f1fb9d020ea6c4f49a593b24719c4a22"
    )
    #expect(
      try DesignRevisionRetentionDigest.releasingRequest(
        operationID: DesignDatabaseOperationID(rawValue: "release-1"),
        claimID: claimID,
        expectedRevision: revision,
        expectedGeneration: 1,
        using: digester
      ).hexadecimalValue
        == "195743ac747e853847e7e4226860df8ad28fcf9eb6ff1a364c6cf0174de4243d"
    )
    #expect(
      try DesignRevisionRetentionDigest.appliedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        claimID: claimID,
        revision: revision,
        generation: 1,
        reachabilityGeneration: 2,
        state: .active,
        using: digester
      ).hexadecimalValue
        == "aeee17a3295dde7da3751902b3debf5bd43624baf505abb52e8f09dbfae5bd27"
    )
    #expect(
      try DesignRevisionRetentionDigest.rejectedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        reason: .generationMismatch(actual: 7),
        using: digester
      ).hexadecimalValue
        == "ca70e84a42105cbc04ce0705c6ff72de0c2b5a9a4fad3c00118e69bf84cf1011"
    )
  }

  private func digest(repeating byte: String) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: byte, count: 32)
    )
  }
}
