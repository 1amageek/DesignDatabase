public struct DesignDisjointMergeBudget: Sendable, Hashable, DesignDatabaseSerializable {
  public let maximumFacetComparisonCount: UInt64
  public let maximumAncestryRevisionCount: UInt64

  public init(
    maximumFacetComparisonCount: UInt64,
    maximumAncestryRevisionCount: UInt64
  ) throws(DesignDatabaseError) {
    guard maximumFacetComparisonCount > 0,
          maximumAncestryRevisionCount > 0 else {
      throw .invalidMergeRequest(
        reason: "Every disjoint-merge budget must be greater than zero."
      )
    }
    self.maximumFacetComparisonCount = maximumFacetComparisonCount
    self.maximumAncestryRevisionCount = maximumAncestryRevisionCount
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumFacetComparisonCount: container.decode(
          UInt64.self,
          forKey: .maximumFacetComparisonCount
        ),
        maximumAncestryRevisionCount: container.decode(
          UInt64.self,
          forKey: .maximumAncestryRevisionCount
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
