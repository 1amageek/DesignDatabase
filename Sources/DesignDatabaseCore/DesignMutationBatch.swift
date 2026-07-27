public struct DesignMutationBatch: Sendable, Hashable, Codable {
  public let mutations: [DesignMutation]

  public init(mutations: [DesignMutation]) {
    self.mutations = mutations
  }
}
