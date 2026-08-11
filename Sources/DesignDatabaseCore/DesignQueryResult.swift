public struct DesignQueryResult: Sendable, DesignDatabaseSerializable {
  public let records: [DesignEntityRecord]
  public let explain: DesignQueryExplain

  public init(records: [DesignEntityRecord], explain: DesignQueryExplain) {
    self.records = records
    self.explain = explain
  }
}
