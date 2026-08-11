public struct DesignDisjointMergePublicationBudget:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public let maximumProjectionCount: UInt64
  public let maximumPhysicalIdentityCount: UInt64

  public init(
    maximumProjectionCount: UInt64,
    maximumPhysicalIdentityCount: UInt64
  ) throws(DesignDatabaseError) {
    guard maximumProjectionCount > 0,
          maximumPhysicalIdentityCount > 0 else {
      throw .invalidMergeRequest(
        reason: "Every disjoint-merge publication budget must be greater than zero."
      )
    }
    self.maximumProjectionCount = maximumProjectionCount
    self.maximumPhysicalIdentityCount = maximumPhysicalIdentityCount
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        maximumProjectionCount: container.decode(
          UInt64.self,
          forKey: .maximumProjectionCount
        ),
        maximumPhysicalIdentityCount: container.decode(
          UInt64.self,
          forKey: .maximumPhysicalIdentityCount
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
