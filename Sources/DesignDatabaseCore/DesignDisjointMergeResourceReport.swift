public struct DesignDisjointMergeResourceReport: Sendable, Hashable, DesignDatabaseSerializable {
  public let facetComparisonCount: UInt64
  public let ancestryRevisionReadCount: UInt64
  public let maximumFacetComparisonCount: UInt64
  public let maximumAncestryRevisionCount: UInt64

  public init(
    facetComparisonCount: UInt64,
    ancestryRevisionReadCount: UInt64,
    maximumFacetComparisonCount: UInt64,
    maximumAncestryRevisionCount: UInt64
  ) {
    self.facetComparisonCount = facetComparisonCount
    self.ancestryRevisionReadCount = ancestryRevisionReadCount
    self.maximumFacetComparisonCount = maximumFacetComparisonCount
    self.maximumAncestryRevisionCount = maximumAncestryRevisionCount
  }
}
