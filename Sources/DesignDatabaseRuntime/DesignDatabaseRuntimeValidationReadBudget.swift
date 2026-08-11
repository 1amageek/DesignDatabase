package actor DesignDatabaseRuntimeValidationReadBudget {
  private let limit: UInt64
  private var consumed: UInt64 = 0
  private var isClosed = false

  package init(limit: UInt64) {
    self.limit = limit
  }

  package func reserve(
    _ requested: UInt64
  ) throws(DesignDatabaseRuntimeReadError) {
    guard !isClosed else { throw .snapshotClosed }
    let (next, overflow) = consumed.addingReportingOverflow(requested)
    guard !overflow, next <= limit else {
      throw .budgetExceeded(
        limit: limit,
        requested: overflow ? UInt64.max : next
      )
    }
    consumed = next
  }

  package func close() {
    isClosed = true
  }
}
