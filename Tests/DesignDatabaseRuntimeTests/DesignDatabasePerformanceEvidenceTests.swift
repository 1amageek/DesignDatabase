import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import Testing

@Suite("DesignDatabase retained performance evidence")
struct DesignDatabasePerformanceEvidenceTests {
  @Test("Decoded-page cache evidence remains source-bound and internally consistent")
  func decodedPageCacheEvidence() throws {
    let resourceURL = try #require(
      Bundle.module.url(
        forResource: "decoded-page-cache-entity-projection-2026-08-11",
        withExtension: "json"
      )
    )
    let evidence = try JSONDecoder().decode(
      DecodedPageCacheEvidence.self,
      from: Data(contentsOf: resourceURL)
    )

    #expect(evidence.schemaVersion == 1)
    #expect(evidence.qualification == "behaviorallyVerified")
    #expect(evidence.correctness.coldWarmRowsEqual)
    #expect(evidence.correctness.coldWarmReportsEqual)
    #expect(evidence.workload.resultRowCount > 0)
    #expect(
      evidence.correctness.canonicalSequenceDigest.count == 64
    )
    #expect(
      evidence.warm.databaseReadCount
        == evidence.cold.databaseReadCount
    )
    #expect(
      evidence.warm.decodeAttemptCount
        == evidence.cold.decodeAttemptCount
    )
    #expect(
      evidence.warm.payloadMaterializationByteCount
        == evidence.cold.payloadMaterializationByteCount
    )
    #expect(evidence.warm.hitCount > evidence.cold.hitCount)
    #expect(
      evidence.warm.avoidedPayloadMaterializationByteCount
        - evidence.cold.avoidedPayloadMaterializationByteCount
        == evidence.workload.encodedPageByteCount
    )
    #expect(evidence.warm.activeLeaseCount == 0)

    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    for source in evidence.source.fileDigests {
      let sourceURL = packageRoot.appendingPathComponent(source.relativePath)
      let bytes = Array(try Data(contentsOf: sourceURL))
      #expect(try digest(bytes).hexadecimalValue == source.sha256)
    }
  }

  private func digest(_ bytes: [UInt8]) throws -> ContentDigest {
    let byteCount = UInt64(bytes.count)
    let limits = try ContentDigestSessionLimits(
      maximumChunkByteCount: max(byteCount, 1),
      maximumTotalByteCount: max(byteCount, 1),
      maximumUpdateCount: 1
    )
    return try SHA256ContentDigester().digest(
      using: .sha256,
      limits: limits
    ) {
      (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
      try lease.update(bytes)
    }.digest
  }
}

private struct DecodedPageCacheEvidence: Decodable {
  struct Source: Decodable {
    struct FileDigest: Decodable {
      let relativePath: String
      let sha256: String
    }

    let fileDigests: [FileDigest]
  }

  struct Workload: Decodable {
    let resultRowCount: UInt64
    let encodedPageByteCount: UInt64
  }

  struct Correctness: Decodable {
    let coldWarmRowsEqual: Bool
    let coldWarmReportsEqual: Bool
    let canonicalSequenceDigest: String
  }

  struct Metrics: Decodable {
    let hitCount: UInt64
    let databaseReadCount: UInt64
    let decodeAttemptCount: UInt64
    let payloadMaterializationByteCount: UInt64
    let avoidedPayloadMaterializationByteCount: UInt64
    let activeLeaseCount: UInt64
  }

  let schemaVersion: Int
  let qualification: String
  let source: Source
  let workload: Workload
  let correctness: Correctness
  let cold: Metrics
  let warm: Metrics
}
