import CircuiteFoundation

public struct DesignQueryPageValidator: Sendable {
  public init() {}

  public func validate(
    _ page: DesignQueryPage,
    for request: DesignQueryRequest,
    expectedRevision: DesignRevisionReference,
    expectedDesignSchemaBundleDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    guard page.revision == expectedRevision else {
      throw .invalidQuery("The query page belongs to another revision.")
    }
    guard page.designSchemaBundleDigest
      == expectedDesignSchemaBundleDigest else {
      throw .invalidQuery("The query page belongs to another schema bundle.")
    }
    guard let rowCount = UInt64(exactly: page.rows.count),
          rowCount <= request.maximumPageResultCount else {
      throw .invalidQuery("The query page exceeds its requested page limit.")
    }
    if let keyPrefix = request.keyPrefix,
       page.rows.contains(where: { !$0.key.hasPrefix(keyPrefix) }) {
      throw .invalidQuery("The query page contains a key outside its prefix.")
    }
    try validateReport(
      page.report,
      previous: request.continuation?.cumulativeReport,
      rowCount: rowCount,
      budget: request.budget
    )
    if let requestContinuation = request.continuation {
      guard page.projectionSemanticDigest
        == requestContinuation.semanticDescriptorDigest,
        page.materialization == requestContinuation.materialization else {
        throw .invalidQueryContinuation(
          "The query page changed materialization while resuming."
        )
      }
    }
    if let pageContinuation = page.continuation {
      guard pageContinuation.family == request.family,
            pageContinuation.budget == request.budget else {
        throw .invalidQueryContinuation(
          "The query page continuation belongs to another request."
        )
      }
      if let requestContinuation = request.continuation {
        guard pageContinuation.normalizedQueryDigest
          == requestContinuation.normalizedQueryDigest else {
          throw .invalidQueryContinuation(
            "The resumed query changed its normalized identity."
          )
        }
      }
    }
  }

  private func validateReport(
    _ report: DesignQueryResourceReport,
    previous: DesignQueryResourceReport?,
    rowCount: UInt64,
    budget: DesignQueryBudget
  ) throws(DesignDatabaseError) {
    guard report.resultCount <= budget.maximumResultCount,
          report.nodeFetchCount <= budget.maximumNodeFetchCount,
          report.encodedReadByteCount
            <= budget.maximumEncodedReadByteCount,
          report.decodedByteCount <= budget.maximumDecodedByteCount,
          report.outputByteCount <= budget.maximumOutputByteCount,
          report.workCount <= budget.maximumWorkCount else {
      throw .invalidQuery("The query page resource report exceeds its budget.")
    }
    guard let previous else {
      guard report.resultCount == rowCount else {
        throw .invalidQuery(
          "The first query page report does not match its row count."
        )
      }
      return
    }
    guard report.resultCount >= previous.resultCount,
          report.nodeFetchCount >= previous.nodeFetchCount,
          report.encodedReadByteCount >= previous.encodedReadByteCount,
          report.decodedByteCount >= previous.decodedByteCount,
          report.outputByteCount >= previous.outputByteCount,
          report.workCount >= previous.workCount else {
      throw .invalidQueryContinuation(
        "The query page resource report moved backwards."
      )
    }
    guard report.resultCount - previous.resultCount == rowCount else {
      throw .invalidQueryContinuation(
        "The resumed query report does not match its new row count."
      )
    }
  }
}
