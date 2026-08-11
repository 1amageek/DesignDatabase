import CircuiteFoundation

public struct DesignQueryContinuation: Sendable, Hashable, DesignDatabaseSerializable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let revision: DesignRevisionReference
  public let family: DesignProjectionFamily
  public let semanticDescriptorDigest: ContentDigest
  public let materialization: DesignProjectionMaterializationReference
  public let normalizedQueryDigest: ContentDigest
  public let lastConsumedKey: DesignCanonicalKey
  public let budget: DesignQueryBudget
  public let cumulativeReport: DesignQueryResourceReport

  public init(
    revision: DesignRevisionReference,
    family: DesignProjectionFamily,
    semanticDescriptorDigest: ContentDigest,
    materialization: DesignProjectionMaterializationReference,
    normalizedQueryDigest: ContentDigest,
    lastConsumedKey: DesignCanonicalKey,
    budget: DesignQueryBudget,
    cumulativeReport: DesignQueryResourceReport
  ) throws(DesignDatabaseError) {
    guard cumulativeReport.resultCount <= budget.maximumResultCount,
          cumulativeReport.nodeFetchCount <= budget.maximumNodeFetchCount,
          cumulativeReport.encodedReadByteCount
            <= budget.maximumEncodedReadByteCount,
          cumulativeReport.decodedByteCount <= budget.maximumDecodedByteCount,
          cumulativeReport.outputByteCount <= budget.maximumOutputByteCount,
          cumulativeReport.workCount <= budget.maximumWorkCount else {
      throw .invalidQueryContinuation(
        "A continuation resource report exceeds its original query budget."
      )
    }
    self.schemaVersion = Self.currentSchemaVersion
    self.revision = revision
    self.family = family
    self.semanticDescriptorDigest = semanticDescriptorDigest
    self.materialization = materialization
    self.normalizedQueryDigest = normalizedQueryDigest
    self.lastConsumedKey = lastConsumedKey
    self.budget = budget
    self.cumulativeReport = cumulativeReport
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case revision
    case family
    case semanticDescriptorDigest
    case materialization
    case normalizedQueryDigest
    case lastConsumedKey
    case budget
    case cumulativeReport
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw DecodingError.dataCorruptedError(
        forKey: .schemaVersion,
        in: container,
        debugDescription: "The query continuation schema version is unsupported."
      )
    }
    do {
      try self.init(
        revision: container.decode(
          DesignRevisionReference.self,
          forKey: .revision
        ),
        family: container.decode(
          DesignProjectionFamily.self,
          forKey: .family
        ),
        semanticDescriptorDigest: container.decode(
          ContentDigest.self,
          forKey: .semanticDescriptorDigest
        ),
        materialization: container.decode(
          DesignProjectionMaterializationReference.self,
          forKey: .materialization
        ),
        normalizedQueryDigest: container.decode(
          ContentDigest.self,
          forKey: .normalizedQueryDigest
        ),
        lastConsumedKey: container.decode(
          DesignCanonicalKey.self,
          forKey: .lastConsumedKey
        ),
        budget: container.decode(DesignQueryBudget.self, forKey: .budget),
        cumulativeReport: container.decode(
          DesignQueryResourceReport.self,
          forKey: .cumulativeReport
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif
}
