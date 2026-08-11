import CircuiteFoundation

public struct DesignDisjointMergeConflict: Sendable, Hashable, DesignDatabaseSerializable {
  public enum Kind: String, Sendable, Hashable, DesignDatabaseSerializable {
    case baseNotAncestor
    case schemaDivergence
    case dependencyRootDivergence
    case semanticDependencyGraphDivergence
    case overlappingFacetChange
  }

  public let kind: Kind
  public let revisions: [DesignRevisionReference]
  public let facetIDs: [DesignFacetID]
  public let reason: String
  public let resourceReport: DesignDisjointMergeResourceReport

  public init(
    kind: Kind,
    revisions: [DesignRevisionReference],
    facetIDs: [DesignFacetID] = [],
    reason: String,
    resourceReport: DesignDisjointMergeResourceReport
  ) {
    self.kind = kind
    self.revisions = revisions
    self.facetIDs = facetIDs.sorted { $0.rawValue < $1.rawValue }
    self.reason = reason
    self.resourceReport = resourceReport
  }
}
