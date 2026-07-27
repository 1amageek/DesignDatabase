public struct DesignFieldSchema: Sendable, Hashable, Codable {
  public let id: DesignFieldID
  public let valueKind: DesignValueKind
  public let isRequired: Bool
  public let isNameIndexSource: Bool

  public init(
    id: DesignFieldID,
    valueKind: DesignValueKind,
    isRequired: Bool = false,
    isNameIndexSource: Bool = false
  ) {
    self.id = id
    self.valueKind = valueKind
    self.isRequired = isRequired
    self.isNameIndexSource = isNameIndexSource
  }
}
