import Database

public struct DesignDatabaseRuntimeReadPage<Model: Persistable>: Sendable {
  public let items: [Model]
  public let continuation: DatabaseScanContinuation?

  public init(
    items: [Model],
    continuation: DatabaseScanContinuation?
  ) {
    self.items = items
    self.continuation = continuation
  }
}
