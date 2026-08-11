import CircuiteFoundation

public struct DesignQueryPage: Sendable, Hashable, DesignDatabaseSerializable {
  public let revision: DesignRevisionReference
  public let designSchemaBundleDigest: ContentDigest
  public let projectionSemanticDigest: ContentDigest
  public let materialization: DesignProjectionMaterializationReference
  public let rows: [DesignProjectionEntry]
  public let continuation: DesignQueryContinuation?
  public let completion: DesignQueryCompletion
  public let report: DesignQueryResourceReport

  public init(
    revision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    projectionSemanticDigest: ContentDigest,
    materialization: DesignProjectionMaterializationReference,
    rows: [DesignProjectionEntry],
    continuation: DesignQueryContinuation?,
    completion: DesignQueryCompletion,
    report: DesignQueryResourceReport
  ) throws(DesignDatabaseError) {
    for index in rows.indices.dropFirst() where
      !(rows[index - 1].key < rows[index].key) {
      throw .invalidQuery(
        "A semantic query page must contain strictly ordered unique keys."
      )
    }
    switch completion {
    case .pageLimitReached:
      guard let continuation, let last = rows.last,
            continuation.revision == revision,
            continuation.semanticDescriptorDigest == projectionSemanticDigest,
            continuation.materialization == materialization,
            continuation.lastConsumedKey == last.key,
            continuation.cumulativeReport == report else {
        throw .invalidQueryContinuation(
          "A page-limit result must carry a continuation bound to its last row and exact materialization."
        )
      }
    case .sourceExhausted, .queryBudgetExhausted:
      guard continuation == nil else {
        throw .invalidQueryContinuation(
          "A terminal semantic query page must not carry a continuation."
        )
      }
    }
    self.revision = revision
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.projectionSemanticDigest = projectionSemanticDigest
    self.materialization = materialization
    self.rows = rows
    self.continuation = continuation
    self.completion = completion
    self.report = report
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case revision
    case designSchemaBundleDigest
    case projectionSemanticDigest
    case materialization
    case rows
    case continuation
    case completion
    case report
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        revision: container.decode(
          DesignRevisionReference.self,
          forKey: .revision
        ),
        designSchemaBundleDigest: container.decode(
          ContentDigest.self,
          forKey: .designSchemaBundleDigest
        ),
        projectionSemanticDigest: container.decode(
          ContentDigest.self,
          forKey: .projectionSemanticDigest
        ),
        materialization: container.decode(
          DesignProjectionMaterializationReference.self,
          forKey: .materialization
        ),
        rows: container.decode([DesignProjectionEntry].self, forKey: .rows),
        continuation: container.decodeIfPresent(
          DesignQueryContinuation.self,
          forKey: .continuation
        ),
        completion: container.decode(
          DesignQueryCompletion.self,
          forKey: .completion
        ),
        report: container.decode(
          DesignQueryResourceReport.self,
          forKey: .report
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif
}
