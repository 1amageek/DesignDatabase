import CircuiteFoundation
import Database
import DesignDatabaseCore
import Foundation

package struct DesignDatabaseRuntimeStagingPhysicalIdentityDirectory: Sendable {
  package static let maximumIdentityCount: UInt64 = 1_048_576
  package static let maximumEncodedByteCount: UInt64 = 134_217_728

  private struct Payload: Sendable, Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let identities: [DesignDatabaseRuntimeImmutableWriteIdentity]

    init(identities: [DesignDatabaseRuntimeImmutableWriteIdentity]) {
      schemaVersion = Self.currentSchemaVersion
      self.identities = identities
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw DecodingError.dataCorruptedError(
          forKey: .schemaVersion,
          in: container,
          debugDescription: "Unsupported staging physical identity directory schema."
        )
      }
      self.schemaVersion = schemaVersion
      identities = try container.decode(
        [DesignDatabaseRuntimeImmutableWriteIdentity].self,
        forKey: .identities
      )
    }

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case identities
    }
  }

  package let identities: [DesignDatabaseRuntimeImmutableWriteIdentity]
  package let encodedPayload: [UInt8]
  package let digest: ContentDigest

  package init(
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    projections: DesignDatabaseRuntimeProjectionStagingDirectory,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    var identities: [DesignDatabaseRuntimeImmutableWriteIdentity] = []
    for record in preparedDirectory.records {
      guard UInt64(record.immutableWriteIdentities.count) == record.writeCount else {
        throw .persistedStateCorrupt(
          reason: "A prepared mutation record has an inconsistent physical identity count."
        )
      }
      identities.append(contentsOf: record.immutableWriteIdentities)
    }
    for entry in projections.entries {
      identities.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim
          .projectionDescriptorIdentity(entry.models.descriptor)
      )
      identities.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim
          .projectionBindingIdentity(entry.models.binding)
      )
      identities.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim
          .projectionMaterializationIdentity(entry.models.materialization)
      )
      for model in entry.models.nodes {
        identities.append(
          try DesignDatabaseRuntimePhysicalCollectionClaim
            .projectionNodeIdentity(model)
        )
      }
    }
    var expectedCount: UInt64 = 0
    for record in preparedDirectory.records {
      let (next, overflow) = expectedCount.addingReportingOverflow(
        record.writeCount
      )
      guard !overflow else {
        throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
          kind: "identity count",
          limit: Self.maximumIdentityCount,
          requested: UInt64.max
        )
      }
      expectedCount = next
    }
    let (projectionMetadataCount, metadataOverflow) = UInt64(
      projections.entries.count
    ).multipliedReportingOverflow(by: 3)
    let (withProjectionNodes, projectionOverflow) = expectedCount
      .addingReportingOverflow(projections.totalNodeCount)
    let (totalExpectedCount, totalOverflow) = withProjectionNodes
      .addingReportingOverflow(projectionMetadataCount)
    guard !metadataOverflow, !projectionOverflow, !totalOverflow,
          let observedCount = UInt64(exactly: identities.count),
          observedCount == totalExpectedCount else {
      throw .persistedStateCorrupt(
        reason: "A staging physical identity directory does not cover every planned write."
      )
    }
    try self.init(identities: identities, using: digester)
  }

  package init(
    model: DesignStagingPhysicalIdentityDirectoryModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    try self.init(
      model: model,
      operation: operation,
      requestDigest: submission.requestDigest,
      planDigest: submission.plan.planDigest,
      candidateRevision: candidateRevision,
      using: digester
    )
  }

  package init(
    model: DesignStagingPhysicalIdentityDirectoryModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    candidateRevision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm
            == requestDigest.algorithm.rawValue,
          model.requestDigestValue
            == requestDigest.hexadecimalValue,
          model.planDigestAlgorithm
            == planDigest.algorithm.rawValue,
          model.planDigestValue
            == planDigest.hexadecimalValue,
          model.candidateRevisionID
            == candidateRevision.revisionID.description else {
      throw .commitStagingConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    let payloadBytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: payloadBytes.count),
          byteCount <= Self.maximumEncodedByteCount else {
      throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
        kind: "encoded bytes",
        limit: Self.maximumEncodedByteCount,
        requested: UInt64(exactly: payloadBytes.count) ?? UInt64.max
      )
    }
    do {
      let observedDigest = try Self.digest(payloadBytes, using: digester)
      guard model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A staging physical identity directory digest does not match its payload."
        )
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(payloadBytes))
      try Self.validateCanonical(
        payload.identities,
        expectedCount: model.identityCount
      )
      identities = payload.identities
      encodedPayload = payloadBytes
      digest = observedDigest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A staging physical identity directory could not be decoded: \(error)"
      )
    }
  }

  package func model(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference
  ) -> DesignStagingPhysicalIdentityDirectoryModel {
    var model = DesignStagingPhysicalIdentityDirectoryModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
    model.requestDigestValue = submission.requestDigest.hexadecimalValue
    model.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
    model.planDigestValue = submission.plan.planDigest.hexadecimalValue
    model.candidateRevisionID = candidateRevision.revisionID.description
    model.identityCount = UInt64(identities.count)
    model.payload = ByteString(encodedPayload)
    model.payloadDigestAlgorithm = digest.algorithm.rawValue
    model.payloadDigestValue = digest.hexadecimalValue
    return model
  }

  private init(
    identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    let ordered = identities.sorted()
    guard let identityCount = UInt64(exactly: ordered.count) else {
      throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
        kind: "identity count",
        limit: Self.maximumIdentityCount,
        requested: UInt64.max
      )
    }
    try Self.validateCanonical(ordered, expectedCount: identityCount)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(Payload(identities: ordered))
      guard let byteCount = UInt64(exactly: data.count),
            byteCount <= Self.maximumEncodedByteCount else {
        throw DesignDatabaseRuntimeError
          .stagingPhysicalIdentityDirectoryBudgetExceeded(
            kind: "encoded bytes",
            limit: Self.maximumEncodedByteCount,
            requested: UInt64(exactly: data.count) ?? UInt64.max
          )
      }
      let encodedPayload = Array(data)
      self.identities = ordered
      self.encodedPayload = encodedPayload
      digest = try Self.digest(encodedPayload, using: digester)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: "A staging physical identity directory could not be encoded: \(error)"
      )
    }
  }

  private static func validateCanonical(
    _ identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    expectedCount: UInt64
  ) throws(DesignDatabaseRuntimeError) {
    guard expectedCount > 0,
          expectedCount <= maximumIdentityCount,
          UInt64(identities.count) == expectedCount else {
      throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
        kind: "identity count",
        limit: maximumIdentityCount,
        requested: expectedCount
      )
    }
    guard identities == identities.sorted(),
          Set(identities).count == identities.count else {
      throw .persistedStateCorrupt(
        reason: "A staging physical identity directory is not sorted and unique."
      )
    }
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.StagingPhysicalIdentityDirectory"
    )
    encoder.append(bytes)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A staging physical identity directory digest could not be computed: \(error)"
      )
    }
  }
}
