import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

package struct DesignProjectionTreeReader: Sendable {
  private let context: DatabaseContext
  private let decodedPageCache: DesignProjectionDecodedPageCache
  private let revision: DesignRevisionReference
  private let designSchemaBundleDigest: ContentDigest
  private let descriptors: [DesignProjectionSemanticDescriptor]
  private let descriptorDigests: [DesignProjectionFamily: ContentDigest]
  private let bindings: DesignProjectionMaterializationBindingSet

  package init(
    context: DatabaseContext,
    decodedPageCache: DesignProjectionDecodedPageCache,
    revision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    descriptors: [DesignProjectionSemanticDescriptor],
    descriptorDigests: [DesignProjectionFamily: ContentDigest],
    bindings: DesignProjectionMaterializationBindingSet
  ) {
    self.context = context
    self.decodedPageCache = decodedPageCache
    self.revision = revision
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.descriptors = descriptors
    self.descriptorDigests = descriptorDigests
    self.bindings = bindings
  }

  package func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    do {
      return try await DesignDatabaseRuntimeStorageSecurity
        .withAuthorizedAccess {
          try await self.queryWithAuthorizedStorage(request)
        }
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .persistence(
        "The storage authorization boundary returned an unexpected failure: \(error)"
      )
    }
  }

  private func queryWithAuthorizedStorage(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    guard let descriptor = descriptors.first(where: {
      $0.family == request.family
    }), let descriptorDigest = descriptorDigests[request.family],
       let materialization = bindings[request.family] else {
      throw .projectionUnavailable(request.family)
    }
    let queryDigest: ContentDigest
    do {
      queryDigest = try normalizedQueryDigest(request)
    } catch {
      throw .contentDigest(String(describing: error))
    }
    let cumulative = request.continuation?.cumulativeReport
      ?? DesignQueryResourceReport()
    if let continuation = request.continuation {
      guard continuation.revision == revision,
            continuation.family == request.family,
            continuation.semanticDescriptorDigest == descriptorDigest,
            continuation.materialization == materialization,
            continuation.normalizedQueryDigest == queryDigest,
            continuation.budget == request.budget else {
        throw .invalidQueryContinuation(
          "The continuation is not bound to this exact revision, projection, materialization, and query."
        )
      }
      try validateReport(cumulative, within: request.budget)
    }
    guard cumulative.resultCount < request.budget.maximumResultCount else {
      return try DesignQueryPage(
        revision: revision,
        designSchemaBundleDigest: designSchemaBundleDigest,
        projectionSemanticDigest: descriptorDigest,
        materialization: materialization,
        rows: [],
        continuation: nil,
        completion: .queryBudgetExhausted,
        report: cumulative
      )
    }
    let remainingResults = request.budget.maximumResultCount
      - cumulative.resultCount
    let pageLimit = min(request.maximumPageResultCount, remainingResults)
    guard let pageLimitCount = Int(exactly: pageLimit) else {
      throw .resourceExhausted(
        limit: UInt64(Int.max),
        requested: pageLimit
      )
    }
    var traversal = DesignProjectionQueryTraversal(
      context: context,
      decodedPageCache: decodedPageCache,
      family: request.family,
      descriptor: descriptor,
      materialization: materialization,
      prefix: request.keyPrefix,
      lastConsumedKey: request.continuation?.lastConsumedKey,
      pageLimit: pageLimitCount,
      budget: request.budget,
      report: cumulative
    )
    let stop: DesignProjectionQueryTraversal.Stop
    do {
      stop = try await traversal.run()
    } catch let error as DesignDatabaseRuntimeError {
      throw .corruption(String(describing: error))
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .persistence(String(describing: error))
    }
    let rows = Array(traversal.matches.prefix(pageLimitCount))
    let completion: DesignQueryCompletion
    let continuation: DesignQueryContinuation?
    switch stop {
    case .sourceExhausted:
      completion = .sourceExhausted
      continuation = nil
    case .budgetExhausted:
      completion = .queryBudgetExhausted
      continuation = nil
    case .pageLimitReached:
      if pageLimit == remainingResults {
        completion = .queryBudgetExhausted
        continuation = nil
      } else if let last = rows.last {
        completion = .pageLimitReached
        continuation = try DesignQueryContinuation(
          revision: revision,
          family: request.family,
          semanticDescriptorDigest: descriptorDigest,
          materialization: materialization,
          normalizedQueryDigest: queryDigest,
          lastConsumedKey: last.key,
          budget: request.budget,
          cumulativeReport: traversal.report
        )
      } else {
        throw .corruption(
          "A projection traversal reached a page limit without returning a row."
        )
      }
    }
    return try DesignQueryPage(
      revision: revision,
      designSchemaBundleDigest: designSchemaBundleDigest,
      projectionSemanticDigest: descriptorDigest,
      materialization: materialization,
      rows: rows,
      continuation: continuation,
      completion: completion,
      report: traversal.report
    )
  }

  private func normalizedQueryDigest(
    _ request: DesignQueryRequest
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.SemanticQuery"
    )
    encoder.append(request.family.rawValue)
    encoder.append(request.keyPrefix == nil ? UInt16(0) : UInt16(1))
    if let prefix = request.keyPrefix { encoder.append(prefix.bytes) }
    encoder.append(request.maximumPageResultCount)
    encoder.append(request.budget.maximumResultCount)
    encoder.append(request.budget.maximumNodeFetchCount)
    encoder.append(request.budget.maximumEncodedReadByteCount)
    encoder.append(request.budget.maximumDecodedByteCount)
    encoder.append(request.budget.maximumOutputByteCount)
    encoder.append(request.budget.maximumWorkCount)
    return try encoder.finalize(using: SHA256ContentDigester())
  }

  private func validateReport(
    _ report: DesignQueryResourceReport,
    within budget: DesignQueryBudget
  ) throws(DesignDatabaseError) {
    guard report.resultCount <= budget.maximumResultCount,
          report.nodeFetchCount <= budget.maximumNodeFetchCount,
          report.encodedReadByteCount <= budget.maximumEncodedReadByteCount,
          report.decodedByteCount <= budget.maximumDecodedByteCount,
          report.outputByteCount <= budget.maximumOutputByteCount,
          report.workCount <= budget.maximumWorkCount else {
      throw .invalidQueryContinuation(
        "The continuation contains resource counters outside its original budget."
      )
    }
  }
}

private struct DesignProjectionQueryTraversal {
  private enum TraversalControl: Error {
    case budgetExhausted
  }

  enum Stop {
    case sourceExhausted
    case pageLimitReached
    case budgetExhausted
  }

  let context: DatabaseContext
  let decodedPageCache: DesignProjectionDecodedPageCache
  let family: DesignProjectionFamily
  let descriptor: DesignProjectionSemanticDescriptor
  let materialization: DesignProjectionMaterializationReference
  let prefix: DesignCanonicalKey?
  let lastConsumedKey: DesignCanonicalKey?
  let pageLimit: Int
  let budget: DesignQueryBudget
  var report: DesignQueryResourceReport
  var matches: [DesignProjectionEntry] = []
  private var exhaustedBudget = false

  init(
    context: DatabaseContext,
    decodedPageCache: DesignProjectionDecodedPageCache,
    family: DesignProjectionFamily,
    descriptor: DesignProjectionSemanticDescriptor,
    materialization: DesignProjectionMaterializationReference,
    prefix: DesignCanonicalKey?,
    lastConsumedKey: DesignCanonicalKey?,
    pageLimit: Int,
    budget: DesignQueryBudget,
    report: DesignQueryResourceReport
  ) {
    self.context = context
    self.decodedPageCache = decodedPageCache
    self.family = family
    self.descriptor = descriptor
    self.materialization = materialization
    self.prefix = prefix
    self.lastConsumedKey = lastConsumedKey
    self.pageLimit = pageLimit
    self.budget = budget
    self.report = report
  }

  mutating func run() async throws -> Stop {
    do {
      let root = try await fetchNode(materialization.rootNodeDigest)
      defer { root.close() }
      guard root.minimumKey == descriptor.minimumKey,
            root.maximumKey == descriptor.maximumKey,
            root.subtreeEntryCount == descriptor.entryCount else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A projection root does not match its semantic descriptor."
        )
      }
      let foundLookahead = try await visit(root)
      if exhaustedBudget { return .budgetExhausted }
      return foundLookahead ? .pageLimitReached : .sourceExhausted
    } catch TraversalControl.budgetExhausted {
      return .budgetExhausted
    }
  }

  private mutating func visit(
    _ node: DesignProjectionDecodedPageLease
  ) async throws -> Bool {
    switch node.kind {
    case .leaf:
      let startIndex = try leafStartIndex(in: node)
      guard !exhaustedBudget else { return false }
      for index in startIndex..<node.entryCount {
        let entry = node.entry(at: index)
        guard try reserveWork() else { return false }
        if let prefix, !entry.key.hasPrefix(prefix) { break }
        if matches.count == pageLimit {
          matches.append(entry)
          return true
        }
        guard try reserveOutput(for: entry) else { return false }
        matches.append(entry)
      }
      return false

    case .internal:
      try validateChildDirectory(node)
      let startIndex = try childStartIndex(in: node)
      guard !exhaustedBudget else { return false }
      for index in startIndex..<node.childCount {
        let childReference = node.child(at: index)
        guard try reserveWork() else { return false }
        if isPastPrefixRange(childReference) { break }
        guard shouldVisit(childReference) else { continue }
        let child = try await fetchNode(childReference.nodeDigest)
        defer { child.close() }
        guard !exhaustedBudget else { return false }
        guard child.minimumKey == childReference.minimumKey,
              child.maximumKey == childReference.maximumKey,
              child.subtreeEntryCount == childReference.subtreeEntryCount,
              child.subtreeNodeCount == childReference.subtreeNodeCount,
              child.level == childReference.level else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A projection child does not match its parent reference."
          )
        }
        if try await visit(child) { return true }
        if exhaustedBudget { return false }
      }
      return false
    }
  }

  private mutating func leafStartIndex(
    in node: DesignProjectionDecodedPageLease
  ) throws -> Int {
    var result = 0
    if let lastConsumedKey {
      result = try firstIndex(
        count: node.entryCount,
        startingAt: result
      ) { index in
        lastConsumedKey < node.entry(at: index).key
      }
    }
    if let prefix {
      result = try firstIndex(
        count: node.entryCount,
        startingAt: result
      ) { index in
        !(node.entry(at: index).key < prefix)
      }
    }
    return result
  }

  private mutating func childStartIndex(
    in node: DesignProjectionDecodedPageLease
  ) throws -> Int {
    var result = 0
    if let lastConsumedKey {
      result = try firstIndex(
        count: node.childCount,
        startingAt: result
      ) { index in
        lastConsumedKey < node.child(at: index).maximumKey
      }
    }
    if let prefix {
      result = try firstIndex(
        count: node.childCount,
        startingAt: result
      ) { index in
        !(node.child(at: index).maximumKey < prefix)
      }
    }
    return result
  }

  private mutating func firstIndex(
    count: Int,
    startingAt start: Int,
    satisfying predicate: (Int) -> Bool
  ) throws -> Int {
    var lowerBound = start
    var upperBound = count
    while lowerBound < upperBound {
      guard try reserveWork() else { return count }
      let middle = lowerBound + (upperBound - lowerBound) / 2
      if predicate(middle) {
        upperBound = middle
      } else {
        lowerBound = middle + 1
      }
    }
    return lowerBound
  }

  private mutating func fetchNode(
    _ digest: ContentDigest
  ) async throws -> DesignProjectionDecodedPageLease {
    let nextNodeFetch = try adding(report.nodeFetchCount, 1)
    guard nextNodeFetch <= budget.maximumNodeFetchCount else {
      exhaustedBudget = true
      throw TraversalControl.budgetExhausted
    }
    let cacheKey = DesignProjectionDecodedPageKey(
      family: family,
      reference: materialization,
      nodeDigest: digest
    )
    if let cached = try decodedPageCache.borrow(cacheKey) {
      guard try reserveNodeBytes(
        cached.encodedByteCount,
        nextNodeFetch: nextNodeFetch
      ) else {
        cached.close()
        throw TraversalControl.budgetExhausted
      }
      return cached
    }
    let model = try await context.withTransaction { transaction in
      try await transaction.fetch(
        DesignProjectionNodeModel.self,
        identifiedBy: DesignProjectionTreeMaterialization.digestKey(digest),
        consistency: .serializable
      )
    }
    decodedPageCache.recordDatabaseRead(for: cacheKey)
    guard let model else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A projection traversal reached a missing node."
      )
    }
    guard let encodedByteCount = UInt64(model.encodedByteCount) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A projection node has an invalid encoded byte count."
      )
    }
    guard try reserveNodeBytes(
      encodedByteCount,
      nextNodeFetch: nextNodeFetch
    ) else {
      throw TraversalControl.budgetExhausted
    }
    decodedPageCache.recordDecodeAttempt(
      encodedByteCount: encodedByteCount,
      for: cacheKey
    )
    let node = try DesignProjectionPersistedNodeDecoder.decode(
      model,
      expectedDigest: digest,
      family: family,
      reference: materialization,
      digester: SHA256ContentDigester()
    )
    return try decodedPageCache.insertAndBorrow(
      DesignProjectionDecodedPage(node: node),
      for: cacheKey
    )
  }

  private mutating func reserveNodeBytes(
    _ encodedByteCount: UInt64,
    nextNodeFetch: UInt64
  ) throws -> Bool {
    let nextEncoded = try adding(
      report.encodedReadByteCount,
      encodedByteCount
    )
    let nextDecoded = try adding(report.decodedByteCount, encodedByteCount)
    guard nextEncoded <= budget.maximumEncodedReadByteCount,
          nextDecoded <= budget.maximumDecodedByteCount else {
      exhaustedBudget = true
      return false
    }
    report = DesignQueryResourceReport(
      resultCount: report.resultCount,
      nodeFetchCount: nextNodeFetch,
      encodedReadByteCount: nextEncoded,
      decodedByteCount: nextDecoded,
      outputByteCount: report.outputByteCount,
      workCount: report.workCount
    )
    return true
  }

  private mutating func reserveWork() throws -> Bool {
    let next = try adding(report.workCount, 1)
    guard next <= budget.maximumWorkCount else {
      exhaustedBudget = true
      return false
    }
    report = DesignQueryResourceReport(
      resultCount: report.resultCount,
      nodeFetchCount: report.nodeFetchCount,
      encodedReadByteCount: report.encodedReadByteCount,
      decodedByteCount: report.decodedByteCount,
      outputByteCount: report.outputByteCount,
      workCount: next
    )
    return true
  }

  private mutating func reserveOutput(
    for entry: DesignProjectionEntry
  ) throws -> Bool {
    guard let byteCount = UInt64(exactly: entry.key.bytes.count + entry.value.count) else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A projection output byte count exceeds UInt64."
      )
    }
    let nextOutput = try adding(report.outputByteCount, byteCount)
    let nextResult = try adding(report.resultCount, 1)
    guard nextOutput <= budget.maximumOutputByteCount,
          nextResult <= budget.maximumResultCount else {
      exhaustedBudget = true
      return false
    }
    report = DesignQueryResourceReport(
      resultCount: nextResult,
      nodeFetchCount: report.nodeFetchCount,
      encodedReadByteCount: report.encodedReadByteCount,
      decodedByteCount: report.decodedByteCount,
      outputByteCount: nextOutput,
      workCount: report.workCount
    )
    return true
  }

  private func shouldVisit(
    _ child: DesignProjectionChildReference
  ) -> Bool {
    if let lastConsumedKey, !(lastConsumedKey < child.maximumKey) {
      return false
    }
    guard let prefix else { return true }
    if child.maximumKey < prefix { return false }
    guard let upperBound = prefixUpperBound(prefix) else { return true }
    return child.minimumKey.bytes.lexicographicallyPrecedes(upperBound)
  }

  private func isPastPrefixRange(
    _ child: DesignProjectionChildReference
  ) -> Bool {
    guard let prefix, let upperBound = prefixUpperBound(prefix) else {
      return false
    }
    return !child.minimumKey.bytes.lexicographicallyPrecedes(upperBound)
  }

  private func prefixUpperBound(
    _ prefix: DesignCanonicalKey
  ) -> [UInt8]? {
    var bytes = prefix.bytes
    var index = bytes.count
    while index > 0 {
      index -= 1
      if bytes[index] < UInt8.max {
        bytes[index] += 1
        bytes.removeSubrange((index + 1)..<bytes.count)
        return bytes
      }
    }
    return nil
  }

  private mutating func validateChildDirectory(
    _ parent: DesignProjectionDecodedPageLease
  ) throws {
    guard parent.childCount > 0,
          parent.child(at: 0).minimumKey == parent.minimumKey,
          parent.child(at: parent.childCount - 1).maximumKey
            == parent.maximumKey else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A projection internal node has invalid child bounds."
      )
    }
    var count: UInt64 = 0
    var descendantNodeCount: UInt64 = 0
    for index in 0..<parent.childCount {
      guard try reserveWork() else {
        throw TraversalControl.budgetExhausted
      }
      let child = parent.child(at: index)
      guard child.minimumKey <= child.maximumKey,
            child.level + 1 == parent.level else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A projection child range or level is invalid."
        )
      }
      if index > 0,
         !(parent.child(at: index - 1).maximumKey < child.minimumKey) {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "Projection child ranges overlap or are unordered."
        )
      }
      count = try adding(count, child.subtreeEntryCount)
      descendantNodeCount = try adding(
        descendantNodeCount,
        child.subtreeNodeCount
      )
    }
    guard count == parent.subtreeEntryCount,
          try adding(descendantNodeCount, 1) == parent.subtreeNodeCount else {
      throw DesignDatabaseRuntimeError.persistedStateCorrupt(
        reason: "A projection internal subtree count is inconsistent."
      )
    }
  }

  private func adding(
    _ lhs: UInt64,
    _ rhs: UInt64
  ) throws(DesignDatabaseRuntimeError) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else {
      throw .persistedStateCorrupt(
        reason: "A projection query resource counter overflowed."
      )
    }
    return result
  }

}
