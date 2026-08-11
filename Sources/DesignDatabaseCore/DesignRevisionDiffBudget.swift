public struct DesignRevisionDiffBudget: Sendable, Hashable, DesignDatabaseSerializable {
  public let maximumFacetComparisonCount: UInt64

  public init(
    maximumFacetComparisonCount: UInt64
  ) throws(DesignDatabaseError) {
    guard maximumFacetComparisonCount > 0 else {
      throw .invalidRevisionDiff(
        reason: "The revision-diff facet comparison budget must be greater than zero."
      )
    }
    self.maximumFacetComparisonCount = maximumFacetComparisonCount
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumFacetComparisonCount: container.decode(
          UInt64.self,
          forKey: .maximumFacetComparisonCount
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
