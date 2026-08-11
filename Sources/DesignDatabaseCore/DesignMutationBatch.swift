public struct DesignMutationBatch: Sendable, Hashable, DesignDatabaseSerializable {
  public let mutations: [DesignMutation]

  public init(mutations: [DesignMutation]) {
    self.mutations = mutations
  }
}
