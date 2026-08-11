import CircuiteFoundation

public struct DesignProjectionSemanticDescriptor: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let family: DesignProjectionFamily
  public let semanticVersion: DesignProjectionSemanticVersion
  public let entryCount: UInt64
  public let minimumKey: DesignCanonicalKey?
  public let maximumKey: DesignCanonicalKey?
  public let canonicalSequenceDigest: ContentDigest

  public init(
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    entryCount: UInt64,
    minimumKey: DesignCanonicalKey?,
    maximumKey: DesignCanonicalKey?,
    canonicalSequenceDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    if entryCount == 0 {
      guard minimumKey == nil, maximumKey == nil else {
        throw .invalidQuery(
          "An empty semantic projection must not declare key bounds."
        )
      }
    } else {
      guard let minimumKey, let maximumKey, minimumKey <= maximumKey else {
        throw .invalidQuery(
          "A non-empty semantic projection must declare ordered key bounds."
        )
      }
    }
    self.family = family
    self.semanticVersion = semanticVersion
    self.entryCount = entryCount
    self.minimumKey = minimumKey
    self.maximumKey = maximumKey
    self.canonicalSequenceDigest = canonicalSequenceDigest
  }

  public static func < (
    lhs: DesignProjectionSemanticDescriptor,
    rhs: DesignProjectionSemanticDescriptor
  ) -> Bool {
    lhs.family < rhs.family
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case family
    case semanticVersion
    case entryCount
    case minimumKey
    case maximumKey
    case canonicalSequenceDigest
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        family: container.decode(DesignProjectionFamily.self, forKey: .family),
        semanticVersion: container.decode(
          DesignProjectionSemanticVersion.self,
          forKey: .semanticVersion
        ),
        entryCount: container.decode(UInt64.self, forKey: .entryCount),
        minimumKey: container.decodeIfPresent(
          DesignCanonicalKey.self,
          forKey: .minimumKey
        ),
        maximumKey: container.decodeIfPresent(
          DesignCanonicalKey.self,
          forKey: .maximumKey
        ),
        canonicalSequenceDigest: container.decode(
          ContentDigest.self,
          forKey: .canonicalSequenceDigest
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
