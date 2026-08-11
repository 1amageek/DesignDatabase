import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimePreparedMutationRecord:
  Sendable,
  Hashable,
  Codable
{
  public static let currentSchemaVersion = 2

  public let schemaVersion: Int
  public let segmentID: DesignMutationPlanSegmentID
  public let schemaID: DesignSchemaID
  public let domainSchemaVersion: SchemaVersion
  public let adapterVersion: String
  public let targetFacet: DesignFacetID
  public let segmentPayloadDigest: ContentDigest
  public let writeCount: UInt64
  public let facetRootDigest: ContentDigest
  public let changeContributionDigest: ContentDigest
  public let projectionChanges: [DesignProjectionChange]
  public let immutableWriteIdentities: [
    DesignDatabaseRuntimeImmutableWriteIdentity
  ]

  package init(
    segment: DesignMutationPlanSegment,
    mutation: any DesignDatabaseRuntimePreparedMutation
  ) throws(DesignDatabaseRuntimeError) {
    guard mutation.segmentID == segment.id,
          mutation.writeCount > 0,
          mutation.writeCount <= segment.expectedWriteCount else {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation violates its segment record contract."
      )
    }
    self.schemaVersion = Self.currentSchemaVersion
    self.segmentID = segment.id
    self.schemaID = segment.schemaID
    self.domainSchemaVersion = segment.schemaVersion
    self.adapterVersion = segment.adapterVersion
    self.targetFacet = segment.targetFacet
    self.segmentPayloadDigest = segment.payloadDigest
    self.writeCount = mutation.writeCount
    self.facetRootDigest = mutation.facetRootDigest
    self.changeContributionDigest = mutation.changeContributionDigest
    self.projectionChanges = mutation.projectionChanges.sorted()
    self.immutableWriteIdentities = try Self.identities(of: mutation)
  }

  public func validate(
    segment: DesignMutationPlanSegment,
    mutation: any DesignDatabaseRuntimePreparedMutation
  ) throws(DesignDatabaseRuntimeError) {
    guard schemaVersion == Self.currentSchemaVersion,
          segmentID == segment.id,
          schemaID == segment.schemaID,
          domainSchemaVersion == segment.schemaVersion,
          adapterVersion == segment.adapterVersion,
          targetFacet == segment.targetFacet,
          segmentPayloadDigest == segment.payloadDigest,
          writeCount == mutation.writeCount,
          facetRootDigest == mutation.facetRootDigest,
          changeContributionDigest == mutation.changeContributionDigest,
          projectionChanges == mutation.projectionChanges.sorted(),
          immutableWriteIdentities == (try Self.identities(of: mutation)) else {
      throw .persistedStateCorrupt(
        reason: "A restored prepared mutation does not match its persisted record."
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
        debugDescription: "Unsupported prepared mutation record schema."
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
    self.adapterVersion = try container.decode(
      String.self,
      forKey: .adapterVersion
    )
    self.targetFacet = try container.decode(
      DesignFacetID.self,
      forKey: .targetFacet
    )
    self.segmentPayloadDigest = try container.decode(
      ContentDigest.self,
      forKey: .segmentPayloadDigest
    )
    self.writeCount = try container.decode(UInt64.self, forKey: .writeCount)
    self.facetRootDigest = try container.decode(
      ContentDigest.self,
      forKey: .facetRootDigest
    )
    self.changeContributionDigest = try container.decode(
      ContentDigest.self,
      forKey: .changeContributionDigest
    )
    self.projectionChanges = try container.decode(
      [DesignProjectionChange].self,
      forKey: .projectionChanges
    )
    self.immutableWriteIdentities = try container.decode(
      [DesignDatabaseRuntimeImmutableWriteIdentity].self,
      forKey: .immutableWriteIdentities
    )
    guard writeCount > 0,
          UInt64(immutableWriteIdentities.count) == writeCount,
          Set(immutableWriteIdentities).count == immutableWriteIdentities.count,
          projectionChanges == projectionChanges.sorted() else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: "Invalid prepared mutation record ordering or write count."
        )
      )
    }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case segmentID
    case schemaID
    case domainSchemaVersion
    case adapterVersion
    case targetFacet
    case segmentPayloadDigest
    case writeCount
    case facetRootDigest
    case changeContributionDigest
    case projectionChanges
    case immutableWriteIdentities
  }

  private static func identities(
    of mutation: any DesignDatabaseRuntimePreparedMutation
  ) throws(DesignDatabaseRuntimeError)
    -> [DesignDatabaseRuntimeImmutableWriteIdentity]
  {
    var identities: [DesignDatabaseRuntimeImmutableWriteIdentity] = []
    guard let capacity = Int(exactly: mutation.writeCount) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A prepared immutable-write identity count is not representable."
      )
    }
    identities.reserveCapacity(capacity)
    do {
      for index in 0..<mutation.writeCount {
        identities.append(try mutation.immutableWriteIdentity(at: index))
      }
    } catch {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation returned an invalid physical write identity."
      )
    }
    guard Set(identities).count == identities.count else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A prepared mutation contains duplicate physical write identities."
      )
    }
    return identities
  }
}
