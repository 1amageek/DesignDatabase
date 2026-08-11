import CircuiteFoundation

public struct DesignProjectionMaterializationReference: Sendable, Hashable, DesignDatabaseSerializable {
  public let semanticDescriptorDigest: ContentDigest
  public let bindingGeneration: UInt64
  public let physicalCodecVersion: DesignProjectionPhysicalCodecVersion
  public let physicalProfileDigest: ContentDigest
  public let rootNodeDigest: ContentDigest

  public init(
    semanticDescriptorDigest: ContentDigest,
    bindingGeneration: UInt64,
    physicalCodecVersion: DesignProjectionPhysicalCodecVersion,
    physicalProfileDigest: ContentDigest,
    rootNodeDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    guard bindingGeneration > 0 else {
      throw .invalidQuery("A projection binding generation must be greater than zero.")
    }
    self.semanticDescriptorDigest = semanticDescriptorDigest
    self.bindingGeneration = bindingGeneration
    self.physicalCodecVersion = physicalCodecVersion
    self.physicalProfileDigest = physicalProfileDigest
    self.rootNodeDigest = rootNodeDigest
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case semanticDescriptorDigest
    case bindingGeneration
    case physicalCodecVersion
    case physicalProfileDigest
    case rootNodeDigest
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        semanticDescriptorDigest: container.decode(
          ContentDigest.self,
          forKey: .semanticDescriptorDigest
        ),
        bindingGeneration: container.decode(
          UInt64.self,
          forKey: .bindingGeneration
        ),
        physicalCodecVersion: container.decode(
          DesignProjectionPhysicalCodecVersion.self,
          forKey: .physicalCodecVersion
        ),
        physicalProfileDigest: container.decode(
          ContentDigest.self,
          forKey: .physicalProfileDigest
        ),
        rootNodeDigest: container.decode(
          ContentDigest.self,
          forKey: .rootNodeDigest
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
