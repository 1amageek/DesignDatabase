import CircuiteFoundation

public struct DesignDisjointMergeSemanticValidationRequirement:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public enum Kind: String, Sendable, Hashable, DesignDatabaseSerializable {
    case crossFacetComposite
    case dependencyBinding
  }

  public let kind: Kind
  public let facetIDs: [DesignFacetID]

  public init(kind: Kind, facetIDs: [DesignFacetID]) {
    self.kind = kind
    self.facetIDs = facetIDs.sorted { $0.rawValue < $1.rawValue }
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      kind: try container.decode(Kind.self, forKey: .kind),
      facetIDs: try container.decode([DesignFacetID].self, forKey: .facetIDs)
    )
  }
#endif
}
