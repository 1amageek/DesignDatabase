import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore

public struct DesignDatabaseRuntimeValidatedMutationRecord:
  Sendable,
  Hashable,
  Codable
{
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let segmentID: DesignMutationPlanSegmentID
  public let schemaID: DesignSchemaID
  public let domainSchemaVersion: SchemaVersion
  public let adapterVersion: String
  public let targetFacet: DesignFacetID
  public let segmentPayloadDigest: ContentDigest
  public let materializationPayload: [UInt8]
  public let materializationPayloadDigest: ContentDigest

  package init(
    segment: DesignMutationPlanSegment,
    validation: DesignDatabaseRuntimeValidatedMutation,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard validation.segmentID == segment.id else {
      throw .persistedStateCorrupt(
        reason: "A validated mutation does not match its plan segment."
      )
    }
    let payloadDigest: ContentDigest
    do {
      payloadDigest = try DesignMutationPlanDigest.payload(
        validation.materializationPayload,
        using: digester
      )
    } catch {
      throw .commitTransactionFailed(
        reason: "A validated mutation payload could not be digested: \(error)"
      )
    }
    self.schemaVersion = Self.currentSchemaVersion
    self.segmentID = segment.id
    self.schemaID = segment.schemaID
    self.domainSchemaVersion = segment.schemaVersion
    self.adapterVersion = segment.adapterVersion
    self.targetFacet = segment.targetFacet
    self.segmentPayloadDigest = segment.payloadDigest
    self.materializationPayload = validation.materializationPayload
    self.materializationPayloadDigest = payloadDigest
  }

  package func validate(
    segment: DesignMutationPlanSegment,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard schemaVersion == Self.currentSchemaVersion,
          segmentID == segment.id,
          schemaID == segment.schemaID,
          domainSchemaVersion == segment.schemaVersion,
          adapterVersion == segment.adapterVersion,
          targetFacet == segment.targetFacet,
          segmentPayloadDigest == segment.payloadDigest else {
      throw .commitStagingConflict(operation: segment.id.rawValue)
    }
    try validatePayload(using: digester)
  }

  package func validatePayload(
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    do {
      let observed = try DesignMutationPlanDigest.payload(
        materializationPayload,
        using: digester
      )
      guard observed == materializationPayloadDigest else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A validated mutation materialization payload has an invalid digest."
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A validated mutation materialization payload could not be digested: \(error)"
      )
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "Unsupported validated mutation record schema."
      )
    }
    self.schemaVersion = schemaVersion
    self.segmentID = try container.decode(
      DesignMutationPlanSegmentID.self,
      forKey: .segmentID
    )
    self.schemaID = try container.decode(DesignSchemaID.self, forKey: .schemaID)
    self.domainSchemaVersion = try container.decode(
      SchemaVersion.self,
      forKey: .domainSchemaVersion
    )
    self.adapterVersion = try container.decode(String.self, forKey: .adapterVersion)
    self.targetFacet = try container.decode(DesignFacetID.self, forKey: .targetFacet)
    self.segmentPayloadDigest = try container.decode(
      ContentDigest.self,
      forKey: .segmentPayloadDigest
    )
    self.materializationPayload = try container.decode(
      [UInt8].self,
      forKey: .materializationPayload
    )
    self.materializationPayloadDigest = try container.decode(
      ContentDigest.self,
      forKey: .materializationPayloadDigest
    )
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case segmentID
    case schemaID
    case domainSchemaVersion
    case adapterVersion
    case targetFacet
    case segmentPayloadDigest
    case materializationPayload
    case materializationPayloadDigest
  }
}
