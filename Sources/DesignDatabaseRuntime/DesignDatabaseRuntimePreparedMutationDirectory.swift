import CircuiteFoundation
import Database
import DesignDatabaseCore
import Foundation

package struct DesignDatabaseRuntimePreparedMutationDirectory: Sendable {
  package static let maximumEncodedByteCount: UInt64 = 67_108_864

  private struct Payload: Sendable, Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let records: [DesignDatabaseRuntimePreparedMutationRecord]

    init(records: [DesignDatabaseRuntimePreparedMutationRecord]) {
      self.schemaVersion = Self.currentSchemaVersion
      self.records = records
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw DecodingError.dataCorruptedError(
          forKey: .schemaVersion,
          in: container,
          debugDescription: "Unsupported prepared mutation directory schema."
        )
      }
      self.schemaVersion = schemaVersion
      self.records = try container.decode(
        [DesignDatabaseRuntimePreparedMutationRecord].self,
        forKey: .records
      )
    }

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case records
    }
  }

  package let records: [DesignDatabaseRuntimePreparedMutationRecord]
  package let encodedPayload: [UInt8]
  package let digest: ContentDigest

  package init(
    segments: [DesignMutationPlanSegment],
    prepared: [any DesignDatabaseRuntimePreparedMutation],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard segments.count == prepared.count else {
      throw .persistedStateCorrupt(
        reason: "Prepared mutation records do not cover every plan segment."
      )
    }
    var records: [DesignDatabaseRuntimePreparedMutationRecord] = []
    records.reserveCapacity(segments.count)
    for (segment, mutation) in zip(segments, prepared) {
      records.append(
        try DesignDatabaseRuntimePreparedMutationRecord(
          segment: segment,
          mutation: mutation
        )
      )
    }
    try self.init(records: records, using: digester)
  }

  private init(
    records: [DesignDatabaseRuntimePreparedMutationRecord],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(Payload(records: records))
      guard let byteCount = UInt64(exactly: data.count) else {
        throw DesignDatabaseRuntimeError.preparedMutationDirectoryBudgetExceeded(
          limit: Self.maximumEncodedByteCount,
          requested: UInt64.max
        )
      }
      guard byteCount <= Self.maximumEncodedByteCount else {
        throw DesignDatabaseRuntimeError.preparedMutationDirectoryBudgetExceeded(
          limit: Self.maximumEncodedByteCount,
          requested: byteCount
        )
      }
      let encodedPayload = Array(data)
      self.records = records
      self.encodedPayload = encodedPayload
      self.digest = try Self.digest(encodedPayload, using: digester)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: "The prepared mutation directory could not be encoded: \(error)"
      )
    }
  }

  package init(
    model: DesignPreparedMutationDirectoryModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm
            == submission.requestDigest.algorithm.rawValue,
          model.requestDigestValue
            == submission.requestDigest.hexadecimalValue,
          model.planDigestAlgorithm == submission.plan.planDigest.algorithm.rawValue,
          model.planDigestValue == submission.plan.planDigest.hexadecimalValue,
          let expectedRecordCount = UInt64(exactly: submission.plan.segments.count),
          model.recordCount == expectedRecordCount else {
      throw .commitStagingConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    let payloadBytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: payloadBytes.count),
          byteCount <= Self.maximumEncodedByteCount else {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation directory exceeds the Runtime byte limit."
      )
    }
    do {
      let observedDigest = try Self.digest(payloadBytes, using: digester)
      guard model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A prepared mutation directory digest does not match its payload."
        )
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(payloadBytes))
      guard payload.records.count == submission.plan.segments.count else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A prepared mutation directory has an invalid record count."
        )
      }
      for (record, segment) in zip(payload.records, submission.plan.segments) {
        guard record.segmentID == segment.id,
              record.schemaID == segment.schemaID,
              record.domainSchemaVersion == segment.schemaVersion,
              record.adapterVersion == segment.adapterVersion,
              record.targetFacet == segment.targetFacet,
              record.segmentPayloadDigest == segment.payloadDigest else {
          throw DesignDatabaseRuntimeError.commitStagingConflict(
            operation: DesignDatabaseRuntimeOperationClaim.key(operation)
          )
        }
      }
      self.records = payload.records
      self.encodedPayload = payloadBytes
      self.digest = observedDigest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation directory could not be decoded: \(error)"
      )
    }
  }

  package func model(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission
  ) -> DesignPreparedMutationDirectoryModel {
    var model = DesignPreparedMutationDirectoryModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
    model.requestDigestValue = submission.requestDigest.hexadecimalValue
    model.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
    model.planDigestValue = submission.plan.planDigest.hexadecimalValue
    model.recordCount = UInt64(records.count)
    model.payload = ByteString(encodedPayload)
    model.payloadDigestAlgorithm = digest.algorithm.rawValue
    model.payloadDigestValue = digest.hexadecimalValue
    return model
  }

  package static func validateStatus(
    _ model: DesignPreparedMutationDirectoryModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    expectedDigest: ContentDigest,
    expectedRecordCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue,
          model.recordCount == expectedRecordCount else {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation directory does not match its operation status."
      )
    }
    let bytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: bytes.count),
          byteCount <= maximumEncodedByteCount else {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation directory status exceeds the Runtime byte limit."
      )
    }
    do {
      let observedDigest = try digest(bytes, using: digester)
      guard observedDigest == expectedDigest,
            model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A prepared mutation directory status has an invalid digest."
        )
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(bytes))
      guard UInt64(payload.records.count) == expectedRecordCount else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A prepared mutation directory status has an invalid record count."
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation directory status could not be decoded: \(error)"
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
