import CircuiteFoundation

public struct DesignFacetRoot: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let facetID: DesignFacetID
  public let digest: ContentDigest

  public init(
    facetID: DesignFacetID,
    digest: ContentDigest
  ) throws(DesignDatabaseError) {
    guard digest.algorithm == .sha256 else {
      throw .contentDigest("A design facet root must use SHA-256.")
    }
    self.facetID = facetID
    self.digest = digest
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.facetID.rawValue < rhs.facetID.rawValue
  }

  public static func canonicalizing(
    _ roots: [DesignFacetRoot]
  ) throws(DesignDatabaseError) -> [DesignFacetRoot] {
    let ordered = roots.sorted()
    for index in ordered.indices.dropFirst() {
      guard ordered[index - 1].facetID != ordered[index].facetID else {
        throw .invalidMutationPlan(
          reason: "A candidate revision contains duplicate facet roots."
        )
      }
    }
    return ordered
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        facetID: container.decode(DesignFacetID.self, forKey: .facetID),
        digest: container.decode(ContentDigest.self, forKey: .digest)
      )
    } catch {
      throw DecodingError.dataCorruptedError(
        forKey: .digest,
        in: container,
        debugDescription: String(describing: error)
      )
    }
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(facetID, forKey: .facetID)
    try container.encode(digest, forKey: .digest)
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case facetID
    case digest
  }
#endif
}
