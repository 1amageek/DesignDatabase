import CircuiteFoundation
import Database
import DesignDatabaseCore

package struct DesignDatabaseRuntimeCollectionRootAuditor {
  private struct ManifestRecord {
    let model: DesignRevisionManifestModel
    let lifecycleState: DesignDatabaseRuntimeRevisionLifecycleState
    let parents: [DesignRevisionReference]
    let dependencies: DesignDependencyLock
  }

  private let context: DatabaseContext
  private let databaseID: DesignDatabaseID
  private let candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  private let budget: DesignDatabaseRuntimeCollectionRootAuditBudget
  private let digester: any ContentDigesting

  package init(
    context: DatabaseContext,
    databaseID: DesignDatabaseID,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet,
    budget: DesignDatabaseRuntimeCollectionRootAuditBudget,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard candidates.databaseID == databaseID else {
      throw .persistedStateCorrupt(
        reason: "A collection root audit crosses a database boundary."
      )
    }
    self.context = context
    self.databaseID = databaseID
    self.candidates = candidates
    self.budget = budget
    self.digester = digester
  }

  package func audit()
    async throws(DesignDatabaseRuntimeError)
      -> DesignDatabaseRuntimeCollectionRootAuditResult
  {
    var attempt: UInt64 = 0
    var lastExpected: Int64 = 0
    var lastActual: Int64 = 0
    while attempt < budget.maximumGenerationRetryCount {
      attempt += 1
      let before = try await reachabilityGeneration()
      let references = try await scanAll(
        DesignNamedReferenceModel.self,
        maximumCount: budget.maximumReferenceCount,
        kind: "named references"
      )
      let retentions = try await scanAll(
        DesignRevisionRetentionModel.self,
        maximumCount: budget.maximumRetentionCount,
        kind: "retention claims"
      )
      let buildIntents = try await scanAll(
        DesignCommitBuildIntentModel.self,
        maximumCount: budget.maximumBuildIntentCount,
        kind: "commit build intents"
      )
      let manifests = try await scanAll(
        DesignRevisionManifestModel.self,
        maximumCount: budget.maximumManifestCount,
        kind: "revision manifests"
      )
      let lifecycles = try await scanAll(
        DesignRevisionLifecycleModel.self,
        maximumCount: budget.maximumManifestCount,
        kind: "revision lifecycles"
      )
      let after = try await reachabilityGeneration()
      guard before == after else {
        lastExpected = before
        lastActual = after
        continue
      }
      return try analyze(
        reachabilityGeneration: after,
        references: references,
        retentions: retentions,
        buildIntents: buildIntents,
        manifests: manifests,
        lifecycles: lifecycles
      )
    }
    throw .collectionReachabilityChanged(
      expected: lastExpected,
      actual: lastActual
    )
  }

  private func reachabilityGeneration()
    async throws(DesignDatabaseRuntimeError) -> Int64
  {
    do {
      return try await context.withTransaction { transaction in
        try await DesignDatabaseRuntimeReachability.require(
          databaseID: databaseID,
          transaction: transaction
        ).generation
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  private func scanAll<Model: Persistable>(
    _ model: Model.Type,
    maximumCount: UInt64,
    kind: String
  ) async throws(DesignDatabaseRuntimeError) -> [Model] {
    var continuation: DatabaseScanContinuation?
    var result: [Model] = []
    var observedCount: UInt64 = 0
    repeat {
      let pageContinuation = continuation
      let page: DesignDatabaseRuntimeReadPage<Model>
      do {
        page = try await context.withTransaction { transaction in
          let scanned = try await transaction.scan(
            model,
            after: pageContinuation,
            limit: budget.scanPageSize
          )
          return DesignDatabaseRuntimeReadPage(
            items: scanned.items,
            continuation: scanned.continuation
          )
        }
      } catch {
        throw .commitTransactionFailed(reason: String(describing: error))
      }
      guard let pageCount = UInt64(exactly: page.items.count) else {
        throw .collectionRootAuditBudgetExceeded(
          kind: kind,
          limit: maximumCount,
          requested: UInt64.max
        )
      }
      let (nextCount, overflow) = observedCount.addingReportingOverflow(
        pageCount
      )
      guard !overflow, nextCount <= maximumCount else {
        throw .collectionRootAuditBudgetExceeded(
          kind: kind,
          limit: maximumCount,
          requested: overflow ? UInt64.max : nextCount
        )
      }
      observedCount = nextCount
      result.append(contentsOf: page.items)
      continuation = page.continuation
    } while continuation != nil
    return result
  }

  private func analyze(
    reachabilityGeneration: Int64,
    references: [DesignNamedReferenceModel],
    retentions: [DesignRevisionRetentionModel],
    buildIntents: [DesignCommitBuildIntentModel],
    manifests: [DesignRevisionManifestModel],
    lifecycles: [DesignRevisionLifecycleModel]
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeCollectionRootAuditResult
  {
    let lifecycleByRevisionID = try uniqueIndex(
      lifecycles,
      id: \.revisionID,
      kind: "revision lifecycle"
    )
    var manifestByRevisionID: [String: ManifestRecord] = [:]
    for manifest in manifests.sorted(by: { $0.id < $1.id }) {
      guard manifest.databaseID == databaseID.description,
            manifest.id.isEmpty == false,
            manifestByRevisionID[manifest.id] == nil,
            let lifecycle = lifecycleByRevisionID[manifest.id] else {
        throw .persistedStateCorrupt(
          reason: "A revision manifest has an invalid database, duplicate identity, or missing lifecycle."
        )
      }
      let revision = DesignRevisionReference(
        databaseID: databaseID,
        revisionID: try revisionID(manifest.id, kind: "revision manifest")
      )
      let lifecycleState = try DesignDatabaseRuntimeRevisionLifecycle.validate(
        lifecycle,
        revision: revision,
        using: digester
      )
      manifestByRevisionID[manifest.id] = ManifestRecord(
        model: manifest,
        lifecycleState: lifecycleState,
        parents: try parents(of: manifest),
        dependencies: try dependencies(of: manifest)
      )
    }
    for candidate in candidates.revisions {
      guard let record = manifestByRevisionID[candidate.revisionID.description] else {
        throw .revisionNotFound(candidate.revisionID.description)
      }
      switch record.lifecycleState {
      case .visible:
        break
      case .deleting:
        throw .revisionDeleting(candidate.revisionID.description)
      case .collected:
        throw .revisionCollected(candidate.revisionID.description)
      }
    }

    var sourceByRevisionID: [String: String] = [:]
    var rootTokens: [String] = []
    let candidateRevisionIDs = Set(
      candidates.revisions.map(\.revisionID.description)
    )
    for (revisionID, record) in manifestByRevisionID.sorted(
      by: { $0.key < $1.key }
    ) where !candidateRevisionIDs.contains(revisionID) {
      switch record.lifecycleState {
      case .visible, .deleting:
        addRoot(
          revisionID: revisionID,
          source: "persistent-revision:\(revisionID)",
          to: &sourceByRevisionID
        )
        rootTokens.append(
          "persistent-revision:\(revisionID):\(record.lifecycleState.rawValue):\(record.model.stateDigestValue)"
        )
      case .collected:
        break
      }
    }
    for reference in references.sorted(by: { $0.id < $1.id }) {
      guard reference.databaseID == databaseID.description,
            reference.id.isEmpty == false,
            reference.generation > 0 else {
        throw .persistedStateCorrupt(
          reason: "A named reference root is malformed."
        )
      }
      _ = try revisionID(reference.revisionID, kind: "named reference")
      addRoot(
        revisionID: reference.revisionID,
        source: "named-reference:\(reference.id)",
        to: &sourceByRevisionID
      )
      rootTokens.append(
        "reference:\(reference.id):\(reference.revisionID):\(reference.generation)"
      )
    }
    for retention in retentions.sorted(by: { $0.id < $1.id }) {
      guard retention.databaseID == databaseID.description,
            retention.id == retention.claimID,
            retention.generation > 0,
            retention.state == 0 || retention.state == 1 else {
        throw .persistedStateCorrupt(
          reason: "A revision retention root is malformed."
        )
      }
      _ = try revisionID(retention.revisionID, kind: "retention claim")
      let evidenceDigest = try contentDigest(
        algorithm: retention.evidenceDigestAlgorithm,
        value: retention.evidenceDigestValue,
        kind: "retention evidence"
      )
      if retention.state == 0 {
        addRoot(
          revisionID: retention.revisionID,
          source: "retention:\(retention.id)",
          to: &sourceByRevisionID
        )
        rootTokens.append(
          "retention:\(retention.id):\(retention.revisionID):\(retention.generation):\(evidenceDigest.hexadecimalValue)"
        )
      }
    }
    for intent in buildIntents.sorted(by: { $0.id < $1.id }) {
      let recovered = try recoverBuildIntentIdentity(intent)
      let state = try DesignDatabaseRuntimeCommitBuildIntent.validateStatus(
        intent,
        operation: recovered.operation,
        requestDigest: recovered.requestDigest,
        using: digester
      )
      if state == .staging || state == .prepared {
        _ = try revisionID(intent.baseRevisionID, kind: "commit build base")
        addRoot(
          revisionID: intent.baseRevisionID,
          source: "commit-build:\(intent.id)",
          to: &sourceByRevisionID
        )
        rootTokens.append(
          "commit-build:\(intent.id):\(intent.baseRevisionID):\(intent.candidateRevisionID):\(intent.state):\(intent.progressDigestValue)"
        )
      }
    }

    var reachable = Set<String>()
    var queue = sourceByRevisionID.keys.sorted()
    var queueIndex = 0
    var graphEdgeCount: UInt64 = 0
    while queueIndex < queue.count {
      let revisionID = queue[queueIndex]
      queueIndex += 1
      guard reachable.insert(revisionID).inserted else { continue }
      guard let record = manifestByRevisionID[revisionID] else {
        throw .persistedStateCorrupt(
          reason: "A persistent root targets a missing revision manifest."
        )
      }
      switch record.lifecycleState {
      case .visible:
        break
      case .deleting:
        throw .revisionDeleting(try self.revisionID(
          revisionID,
          kind: "reachable revision"
        ).description)
      case .collected:
        throw .revisionCollected(try self.revisionID(
          revisionID,
          kind: "reachable revision"
        ).description)
      }
      if candidates.revisions.contains(where: {
        $0.revisionID.description == revisionID
      }) {
        throw .revisionStillReachable(
          revisionID: revisionID,
          rootKind: sourceByRevisionID[revisionID] ?? "reachable-closure"
        )
      }
      var edges = record.parents.map { $0.revisionID.description }
      for dependency in record.dependencies.entries {
        if case .databaseRevision(let target) = dependency.target,
           target.databaseID == databaseID {
          edges.append(target.revisionID.description)
        }
      }
      edges = Array(Set(edges)).sorted()
      guard let edgeCount = UInt64(exactly: edges.count) else {
        throw .collectionRootAuditBudgetExceeded(
          kind: "revision graph edges",
          limit: budget.maximumGraphEdgeCount,
          requested: UInt64.max
        )
      }
      let (nextEdgeCount, edgeOverflow) = graphEdgeCount.addingReportingOverflow(
        edgeCount
      )
      guard !edgeOverflow, nextEdgeCount <= budget.maximumGraphEdgeCount else {
        throw .collectionRootAuditBudgetExceeded(
          kind: "revision graph edges",
          limit: budget.maximumGraphEdgeCount,
          requested: edgeOverflow ? UInt64.max : nextEdgeCount
        )
      }
      graphEdgeCount = nextEdgeCount
      let source = sourceByRevisionID[revisionID] ?? "reachable-closure"
      for edge in edges {
        if let existing = sourceByRevisionID[edge] {
          sourceByRevisionID[edge] = min(existing, source)
        } else {
          sourceByRevisionID[edge] = source
        }
        if !reachable.contains(edge) { queue.append(edge) }
      }
      rootTokens.append(
        "reachable:\(revisionID):\(record.model.stateDigestValue):\(record.model.dependencyRootDigestValue):\(edges.joined(separator: ","))"
      )
    }

    rootTokens.sort()
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CollectionRootSet"
    )
    guard let generation = UInt64(exactly: reachabilityGeneration),
          let tokenCount = UInt64(exactly: rootTokens.count),
          let reachableCount = UInt64(exactly: reachable.count) else {
      throw .persistedStateCorrupt(
        reason: "A collection root audit count or generation is invalid."
      )
    }
    encoder.append(databaseID.description)
    encoder.append(generation)
    encoder.append(tokenCount)
    for token in rootTokens { encoder.append(token) }
    return DesignDatabaseRuntimeCollectionRootAuditResult(
      observedReachabilityGeneration: reachabilityGeneration,
      rootSetDigest: try encoder.finalize(using: digester),
      reachableRevisionCount: reachableCount
    )
  }

  private func parents(
    of manifest: DesignRevisionManifestModel
  ) throws(DesignDatabaseRuntimeError) -> [DesignRevisionReference] {
    guard let expectedCount = Int(exactly: manifest.parentCount),
          expectedCount >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest has an invalid parent count."
      )
    }
    let identifiers = manifest.parentRevisionIDs.isEmpty
      ? []
      : manifest.parentRevisionIDs.split(
          separator: "\n",
          omittingEmptySubsequences: false
        ).map(String.init)
    guard identifiers.count == expectedCount,
          Set(identifiers).count == identifiers.count else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest parent directory is not canonical."
      )
    }
    var result: [DesignRevisionReference] = []
    result.reserveCapacity(identifiers.count)
    for identifier in identifiers {
      result.append(
        DesignRevisionReference(
          databaseID: databaseID,
          revisionID: try revisionID(identifier, kind: "revision parent")
        )
      )
    }
    return result
  }

  private func dependencies(
    of manifest: DesignRevisionManifestModel
  ) throws(DesignDatabaseRuntimeError) -> DesignDependencyLock {
    let root = try contentDigest(
      algorithm: manifest.dependencyRootDigestAlgorithm,
      value: manifest.dependencyRootDigestValue,
      kind: "dependency root"
    )
    return try DesignDatabaseRuntimeDependencyLockDirectory.decode(
      count: manifest.dependencyLockEntryCount,
      encoded: manifest.dependencyLockEntries,
      expectedRootDigest: root,
      using: digester
    )
  }

  private func recoverBuildIntentIdentity(
    _ intent: DesignCommitBuildIntentModel
  ) throws(DesignDatabaseRuntimeError) -> (
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) {
    do {
      let operation = DesignDatabaseOperationReference(
        databaseID: try DesignDatabaseID(hexadecimalValue: intent.databaseID),
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: intent.subjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(rawValue: intent.operationID)
      )
      guard operation.databaseID == databaseID,
            intent.id == DesignDatabaseRuntimeOperationClaim.key(operation) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A commit build root crosses a database or operation boundary."
        )
      }
      return (
        operation,
        try ContentDigest(
          algorithm: ContentDigestAlgorithm(
            rawValue: intent.requestDigestAlgorithm
          ),
          hexadecimalValue: intent.requestDigestValue
        )
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit build root has a malformed operation or digest."
      )
    }
  }

  private func contentDigest(
    algorithm: String,
    value: String,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      return try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: algorithm),
        hexadecimalValue: value
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A \(kind) digest is malformed."
      )
    }
  }

  private func revisionID(
    _ value: String,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionID {
    do {
      return try DesignRevisionID(hexadecimalValue: value)
    } catch {
      throw .persistedStateCorrupt(
        reason: "A \(kind) revision identity is malformed."
      )
    }
  }

  private func uniqueIndex<Model>(
    _ models: [Model],
    id: KeyPath<Model, String>,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> [String: Model] {
    var result: [String: Model] = [:]
    for model in models {
      let identifier = model[keyPath: id]
      guard identifier.isEmpty == false,
            result.updateValue(model, forKey: identifier) == nil else {
        throw .persistedStateCorrupt(
          reason: "A \(kind) directory contains an empty or duplicate identity."
        )
      }
    }
    return result
  }

  private func addRoot(
    revisionID: String,
    source: String,
    to roots: inout [String: String]
  ) {
    if let existing = roots[revisionID] {
      roots[revisionID] = min(existing, source)
    } else {
      roots[revisionID] = source
    }
  }
}
