import CircuiteFoundation

public struct DesignTransactionState: Sendable {
  public let baseEntities: [DesignEntityID: DesignEntityRecord]
  public let entities: [DesignEntityID: DesignEntityRecord]
  public let changes: [DesignEntityChange]
  public let nextEntityValue: UInt64

  package init(
    baseEntities: [DesignEntityID: DesignEntityRecord],
    entities: [DesignEntityID: DesignEntityRecord],
    changes: [DesignEntityChange],
    nextEntityValue: UInt64
  ) {
    self.baseEntities = baseEntities
    self.entities = entities
    self.changes = changes
    self.nextEntityValue = nextEntityValue
  }
}
