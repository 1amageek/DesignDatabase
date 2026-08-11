import CircuiteFoundation

public struct DesignTransactionOptions: Sendable, Hashable, DesignDatabaseSerializable {
  public let provenance: ExecutionProvenance?
  public let maximumChangedEntities: UInt64

  public init(
    provenance: ExecutionProvenance? = nil,
    maximumChangedEntities: UInt64 = 1_000_000
  ) throws(DesignDatabaseError) {
    guard maximumChangedEntities > 0 else {
      throw DesignDatabaseError.resourceExhausted(limit: 0, requested: 0)
    }
    self.provenance = provenance
    self.maximumChangedEntities = maximumChangedEntities
  }
}
