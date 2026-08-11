import CircuiteFoundation
import Database
import DesignDatabaseCore
import Foundation

package struct DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory: Sendable {
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
          debugDescription: "Unsupported revision physical identity directory schema."
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

  package let revision: DesignRevisionReference
  package let identities: [DesignDatabaseRuntimeImmutableWriteIdentity]
  package let encodedPayload: [UInt8]
  package let digest: ContentDigest

  package init(
    revision: DesignRevisionReference,
    projection: DesignProjectionPersistedModels,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    var identities = [
      try DesignDatabaseRuntimePhysicalCollectionClaim
        .projectionDescriptorIdentity(projection.descriptor),
      try DesignDatabaseRuntimePhysicalCollectionClaim
        .projectionBindingIdentity(projection.binding),
      try DesignDatabaseRuntimePhysicalCollectionClaim
        .projectionMaterializationIdentity(projection.materialization),
    ]
    for node in projection.nodes {
      identities.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim
          .projectionNodeIdentity(node)
      )
    }
    try self.init(
      revision: revision,
      identities: identities,
      using: digester
    )
  }

  package init(
    revision: DesignRevisionReference,
    identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    let ordered = identities.sorted()
    guard !ordered.isEmpty,
          let identityCount = UInt64(exactly: ordered.count),
          identityCount
            <= DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
              .maximumIdentityCount else {
      throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
        kind: "revision identity count",
        limit: DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
          .maximumIdentityCount,
        requested: UInt64(exactly: ordered.count) ?? UInt64.max
      )
    }
    guard Set(ordered).count == ordered.count else {
      throw .persistedStateCorrupt(
        reason: "A revision physical identity directory contains duplicate writes."
      )
    }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try encoder.encode(Payload(identities: ordered))
      guard let byteCount = UInt64(exactly: data.count),
            byteCount
              <= DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
                .maximumEncodedByteCount else {
        throw DesignDatabaseRuntimeError
          .stagingPhysicalIdentityDirectoryBudgetExceeded(
            kind: "revision encoded bytes",
            limit: DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
              .maximumEncodedByteCount,
            requested: UInt64(exactly: data.count) ?? UInt64.max
          )
      }
      self.revision = revision
      self.identities = ordered
      encodedPayload = Array(data)
      digest = try Self.digest(Array(data), using: digester)
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: "A revision physical identity directory could not be encoded: \(error)"
      )
    }
  }

  package init(
    model: DesignRevisionPhysicalIdentityDirectoryModel,
    revision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == revision.revisionID.description,
          model.databaseID == revision.databaseID.description,
          model.revisionID == revision.revisionID.description else {
      throw .persistedStateCorrupt(
        reason: "A revision physical identity directory crossed an exact revision boundary."
      )
    }
    let bytes = Array(model.payload)
    guard let byteCount = UInt64(exactly: bytes.count),
          byteCount
            <= DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
              .maximumEncodedByteCount else {
      throw .stagingPhysicalIdentityDirectoryBudgetExceeded(
        kind: "revision encoded bytes",
        limit: DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
          .maximumEncodedByteCount,
        requested: UInt64(exactly: bytes.count) ?? UInt64.max
      )
    }
    do {
      let observedDigest = try Self.digest(bytes, using: digester)
      guard model.payloadDigestAlgorithm == observedDigest.algorithm.rawValue,
            model.payloadDigestValue == observedDigest.hexadecimalValue else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A revision physical identity directory digest does not match its payload."
        )
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(bytes))
      guard !payload.identities.isEmpty,
            payload.identities == payload.identities.sorted(),
            Set(payload.identities).count == payload.identities.count,
            UInt64(payload.identities.count) == model.identityCount,
            model.identityCount
              <= DesignDatabaseRuntimeStagingPhysicalIdentityDirectory
                .maximumIdentityCount else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A revision physical identity directory is not canonical."
        )
      }
      self.revision = revision
      identities = payload.identities
      encodedPayload = bytes
      digest = observedDigest
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A revision physical identity directory could not be decoded: \(error)"
      )
    }
  }

  package func model() -> DesignRevisionPhysicalIdentityDirectoryModel {
    var model = DesignRevisionPhysicalIdentityDirectoryModel()
    model.id = revision.revisionID.description
    model.databaseID = revision.databaseID.description
    model.revisionID = revision.revisionID.description
    model.identityCount = UInt64(identities.count)
    model.payload = ByteString(encodedPayload)
    model.payloadDigestAlgorithm = digest.algorithm.rawValue
    model.payloadDigestValue = digest.hexadecimalValue
    return model
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.RevisionPhysicalIdentityDirectory"
    )
    encoder.append(bytes)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A revision physical identity directory digest could not be computed: \(error)"
      )
    }
  }
}
