import CircuiteFoundation
import Database
import DesignDatabaseCore
import Foundation

package struct DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory:
  Sendable
{
  package static let maximumEncodedByteCount: UInt64 = 16_777_216

  private struct Payload: Sendable, Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let identities: [DesignDatabaseRuntimeImmutableWriteIdentity]
    let rejectedStagingRootIDs: [String]

    init(
      identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
      rejectedStagingRootIDs: [String]
    ) {
      schemaVersion = Self.currentSchemaVersion
      self.identities = identities
      self.rejectedStagingRootIDs = rejectedStagingRootIDs
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
      guard schemaVersion == Self.currentSchemaVersion else {
        throw DecodingError.dataCorruptedError(
          forKey: .schemaVersion,
          in: container,
          debugDescription: "Unsupported collection physical identity directory schema."
        )
      }
      self.schemaVersion = schemaVersion
      identities = try container.decode(
        [DesignDatabaseRuntimeImmutableWriteIdentity].self,
        forKey: .identities
      )
      rejectedStagingRootIDs = try container.decode(
        [String].self,
        forKey: .rejectedStagingRootIDs
      )
    }

    private enum CodingKeys: String, CodingKey {
      case schemaVersion
      case identities
      case rejectedStagingRootIDs
    }
  }

  package let identities: [DesignDatabaseRuntimeImmutableWriteIdentity]
  package let rejectedStagingRootIDs: [String]
  package let encodedPayload: [UInt8]
  package let digest: ContentDigest
  package let identitySetDigest: ContentDigest

  package init(
    identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    rejectedStagingRootIDs: [String] = [],
    maximumIdentityCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    try Self.validateCanonical(
      identities,
      maximumIdentityCount: maximumIdentityCount
    )
    try Self.validateCanonicalRootIDs(rejectedStagingRootIDs)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(
        Payload(
          identities: identities,
          rejectedStagingRootIDs: rejectedStagingRootIDs
        )
      )
      guard let byteCount = UInt64(exactly: data.count),
            byteCount <= Self.maximumEncodedByteCount else {
        throw DesignDatabaseRuntimeError
          .collectionRootAuditBudgetExceeded(
            kind: "collection physical identity directory bytes",
            limit: Self.maximumEncodedByteCount,
            requested: UInt64(exactly: data.count) ?? UInt64.max
          )
      }
      self.identities = identities
      self.rejectedStagingRootIDs = rejectedStagingRootIDs
      encodedPayload = Array(data)
      digest = try Self.digest(Array(data), using: digester)
      identitySetDigest = try DesignDatabaseRuntimePhysicalCollectionClaim
        .identitySetDigest(identities, using: digester)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: "A collection physical identity directory could not be encoded: \(error)"
      )
    }
  }

  package init(
    model: DesignCollectionPhysicalIdentityDirectoryModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    maximumIdentityCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue else {
      throw .collectionIdempotencyConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    let payloadBytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: payloadBytes.count),
          byteCount <= Self.maximumEncodedByteCount else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "collection physical identity directory bytes",
        limit: Self.maximumEncodedByteCount,
        requested: UInt64(exactly: payloadBytes.count) ?? UInt64.max
      )
    }
    do {
      let observedDigest = try Self.digest(payloadBytes, using: digester)
      guard model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A collection physical identity directory digest does not match its payload."
        )
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(payloadBytes))
      try Self.validateCanonical(
        payload.identities,
        maximumIdentityCount: maximumIdentityCount
      )
      try Self.validateCanonicalRootIDs(payload.rejectedStagingRootIDs)
      guard UInt64(payload.identities.count) == model.identityCount else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A collection physical identity directory count is invalid."
        )
      }
      let identitySetDigest = try DesignDatabaseRuntimePhysicalCollectionClaim
        .identitySetDigest(payload.identities, using: digester)
      guard model.identitySetDigestAlgorithm
              == identitySetDigest.algorithm.rawValue,
            model.identitySetDigestValue
              == identitySetDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A collection physical identity set digest is invalid."
        )
      }
      identities = payload.identities
      rejectedStagingRootIDs = payload.rejectedStagingRootIDs
      encodedPayload = payloadBytes
      digest = observedDigest
      self.identitySetDigest = identitySetDigest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A collection physical identity directory could not be decoded: \(error)"
      )
    }
  }

  package func model(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) -> DesignCollectionPhysicalIdentityDirectoryModel {
    var model = DesignCollectionPhysicalIdentityDirectoryModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    model.identityCount = UInt64(identities.count)
    model.payload = ByteString(encodedPayload)
    model.payloadDigestAlgorithm = digest.algorithm.rawValue
    model.payloadDigestValue = digest.hexadecimalValue
    model.identitySetDigestAlgorithm = identitySetDigest.algorithm.rawValue
    model.identitySetDigestValue = identitySetDigest.hexadecimalValue
    return model
  }

  private static func validateCanonical(
    _ identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    maximumIdentityCount: UInt64
  ) throws(DesignDatabaseRuntimeError) {
    guard maximumIdentityCount > 0,
          let identityCount = UInt64(exactly: identities.count),
          identityCount <= maximumIdentityCount else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "physical collection claims",
        limit: maximumIdentityCount,
        requested: UInt64(exactly: identities.count) ?? UInt64.max
      )
    }
    guard identities == identities.sorted(),
          Set(identities).count == identities.count else {
      throw .persistedStateCorrupt(
        reason: "A collection physical identity directory is not sorted and unique."
      )
    }
  }

  private static func validateCanonicalRootIDs(
    _ rootIDs: [String]
  ) throws(DesignDatabaseRuntimeError) {
    guard rootIDs.allSatisfy({ !$0.isEmpty }),
          rootIDs == rootIDs.sorted(),
          Set(rootIDs).count == rootIDs.count else {
      throw .persistedStateCorrupt(
        reason: "A collection rejected staging root directory is not sorted and unique."
      )
    }
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CollectionPhysicalIdentityDirectory"
    )
    encoder.append(bytes)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A collection physical identity directory digest could not be computed: \(error)"
      )
    }
  }
}
