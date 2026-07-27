public struct DesignQuery: Sendable, Hashable, Codable {
  public let source: DesignQuerySource
  public let predicate: DesignPredicate?
  public let ordering: DesignOrdering
  public let limit: UInt64?
  public let executionPolicy: DesignQueryExecutionPolicy

  public init(
    source: DesignQuerySource,
    predicate: DesignPredicate? = nil,
    ordering: DesignOrdering = .entityIDAscending,
    limit: UInt64? = nil,
    executionPolicy: DesignQueryExecutionPolicy
  ) throws(DesignDatabaseError) {
    if let limit, limit == 0 {
      throw DesignDatabaseError.invalidQuery("Query limit must be positive.")
    }
    self.source = source
    self.predicate = predicate
    self.ordering = ordering
    self.limit = limit
    self.executionPolicy = executionPolicy
  }
}
