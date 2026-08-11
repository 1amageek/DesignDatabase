public struct DesignQueryRequest: Sendable, Hashable, DesignDatabaseSerializable {
  public let family: DesignProjectionFamily
  public let keyPrefix: DesignCanonicalKey?
  public let maximumPageResultCount: UInt64
  public let budget: DesignQueryBudget
  public let continuation: DesignQueryContinuation?

  public init(
    family: DesignProjectionFamily,
    keyPrefix: DesignCanonicalKey? = nil,
    maximumPageResultCount: UInt64,
    budget: DesignQueryBudget,
    continuation: DesignQueryContinuation? = nil
  ) throws(DesignDatabaseError) {
    guard maximumPageResultCount > 0,
          maximumPageResultCount <= budget.maximumResultCount else {
      throw .invalidQuery(
        "The page result limit must be positive and within the whole-query budget."
      )
    }
    if let continuation {
      guard continuation.schemaVersion == DesignQueryContinuation.currentSchemaVersion,
            continuation.family == family,
            continuation.budget == budget else {
        throw .invalidQuery(
          "The continuation does not match the semantic query request."
        )
      }
    }
    self.family = family
    self.keyPrefix = keyPrefix
    self.maximumPageResultCount = maximumPageResultCount
    self.budget = budget
    self.continuation = continuation
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case family
    case keyPrefix
    case maximumPageResultCount
    case budget
    case continuation
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        family: container.decode(
          DesignProjectionFamily.self,
          forKey: .family
        ),
        keyPrefix: container.decodeIfPresent(
          DesignCanonicalKey.self,
          forKey: .keyPrefix
        ),
        maximumPageResultCount: container.decode(
          UInt64.self,
          forKey: .maximumPageResultCount
        ),
        budget: container.decode(DesignQueryBudget.self, forKey: .budget),
        continuation: container.decodeIfPresent(
          DesignQueryContinuation.self,
          forKey: .continuation
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
