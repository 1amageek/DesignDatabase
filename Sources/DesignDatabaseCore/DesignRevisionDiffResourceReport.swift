public struct DesignRevisionDiffResourceReport: Sendable, Hashable, DesignDatabaseSerializable {
  public let facetComparisonCount: UInt64
  public let maximumFacetComparisonCount: UInt64

  public init(
    facetComparisonCount: UInt64,
    maximumFacetComparisonCount: UInt64
  ) {
    self.facetComparisonCount = facetComparisonCount
    self.maximumFacetComparisonCount = maximumFacetComparisonCount
  }
}
