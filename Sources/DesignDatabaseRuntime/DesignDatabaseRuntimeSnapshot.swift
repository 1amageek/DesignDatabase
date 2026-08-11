import CircuiteFoundation
import Database
import DesignDatabaseCore

public actor DesignDatabaseRuntimeSnapshot: DesignReadSnapshot {
  private enum State {
    case open
    case closing
    case closed
  }

  public nonisolated let revision: DesignRevisionReference
  public nonisolated let parents: [DesignRevisionReference]
  public nonisolated let stateDigest: ContentDigest
  public nonisolated let designSchemaBundle: DesignSchemaBundle
  public nonisolated let designSchemaBundleDigest: ContentDigest
  public nonisolated let directDependencyLock: DesignDependencyLock
  public nonisolated let dependencyRootDigest: ContentDigest
  public nonisolated let semanticDependencyGraphDigest: ContentDigest
  public nonisolated let facetRoots: [DesignFacetRoot]
  public nonisolated let directChangeRootDigest: ContentDigest
  public nonisolated let projectionSemantics: [DesignProjectionSemanticDescriptor]
  public nonisolated let materializationBindings: DesignProjectionMaterializationBindingSet

  private let identifier: UInt64
  private let registry: DesignDatabaseRuntimeSnapshotRegistry
  private let snapshotLease: DesignDatabaseRuntimeSnapshotLease
  private let leaseCoordinator: DesignDatabaseRuntimeLeaseCoordinator
  private let context: DatabaseContext
  private let decodedPageCache: DesignProjectionDecodedPageCache
  private let projectionDescriptorDigests: [DesignProjectionFamily: ContentDigest]
  private var state: State = .open
  private var activeRuntimeReadCount: UInt64 = 0
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []

  package init(
    identifier: UInt64,
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference],
    stateDigest: ContentDigest,
    designSchemaBundle: DesignSchemaBundle,
    designSchemaBundleDigest: ContentDigest,
    directDependencyLock: DesignDependencyLock,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    directChangeRootDigest: ContentDigest,
    projectionSemantics: [DesignProjectionSemanticDescriptor],
    projectionDescriptorDigests: [DesignProjectionFamily: ContentDigest],
    materializationBindings: DesignProjectionMaterializationBindingSet,
    snapshotLease: DesignDatabaseRuntimeSnapshotLease,
    context: DatabaseContext,
    decodedPageCache: DesignProjectionDecodedPageCache,
    leaseCoordinator: DesignDatabaseRuntimeLeaseCoordinator,
    registry: DesignDatabaseRuntimeSnapshotRegistry
  ) {
    self.identifier = identifier
    self.revision = revision
    self.parents = parents
    self.stateDigest = stateDigest
    self.designSchemaBundle = designSchemaBundle
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.directDependencyLock = directDependencyLock
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.facetRoots = facetRoots
    self.directChangeRootDigest = directChangeRootDigest
    self.projectionSemantics = projectionSemantics
    self.projectionDescriptorDigests = projectionDescriptorDigests
    self.materializationBindings = materializationBindings
    self.snapshotLease = snapshotLease
    self.context = context
    self.decodedPageCache = decodedPageCache
    self.leaseCoordinator = leaseCoordinator
    self.registry = registry
  }

  public func withRuntimeReads<Result: Sendable>(
    maximumReadCount: UInt64,
    _ operation: @Sendable (DesignDatabaseRuntimeReadSnapshot) async throws -> Result
  ) async throws -> Result {
    guard case .open = state else {
      throw DesignDatabaseRuntimeReadError.snapshotClosed
    }
    let (nextCount, overflow) = activeRuntimeReadCount.addingReportingOverflow(1)
    guard !overflow else {
      throw DesignDatabaseRuntimeReadError.budgetExceeded(
        limit: UInt64.max,
        requested: UInt64.max
      )
    }
    activeRuntimeReadCount = nextCount
    let reads = DesignDatabaseRuntimeReadSnapshot(
      context: context,
      revision: revision,
      maximumReadCount: maximumReadCount
    )
    do {
      let result = try await operation(reads)
      await finishRuntimeReads(reads)
      return result
    } catch {
      await finishRuntimeReads(reads)
      throw error
    }
  }

  public func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    guard case .open = state else { throw .closed }
    let (nextCount, overflow) = activeRuntimeReadCount.addingReportingOverflow(1)
    guard !overflow else {
      throw .resourceExhausted(limit: UInt64.max, requested: UInt64.max)
    }
    activeRuntimeReadCount = nextCount
    do {
      let page = try await queryOperation(request)
      finishActiveRead()
      return page
    } catch let error {
      finishActiveRead()
      throw error
    }
  }

  package func decodedProjectionPageCacheMetrics()
    -> DesignProjectionDecodedPageCacheMetrics {
    decodedPageCache.metrics()
  }

  private func queryOperation(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage {
    try await DesignProjectionTreeReader(
      context: context,
      decodedPageCache: decodedPageCache,
      revision: revision,
      designSchemaBundleDigest: designSchemaBundleDigest,
      descriptors: projectionSemantics,
      descriptorDigests: projectionDescriptorDigests,
      bindings: materializationBindings
    ).query(request)
  }

  public func close() async -> DesignSnapshotTermination {
    switch state {
    case .closed:
      return .alreadyClosed
    case .closing:
      await withCheckedContinuation { continuation in
        closeWaiters.append(continuation)
      }
      return .alreadyClosed
    case .open:
      state = .closing
    }
    if activeRuntimeReadCount > 0 {
      await withCheckedContinuation { continuation in
        drainWaiters.append(continuation)
      }
    }
    await leaseCoordinator.release(snapshotLease)
    await registry.release(identifier: identifier)
    state = .closed
    let waiters = closeWaiters
    closeWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
    return .closed
  }

  private func finishRuntimeReads(
    _ reads: DesignDatabaseRuntimeReadSnapshot
  ) async {
    await reads.close()
    finishActiveRead()
  }

  private func finishActiveRead() {
    precondition(activeRuntimeReadCount > 0)
    activeRuntimeReadCount -= 1
    guard activeRuntimeReadCount == 0 else { return }
    let waiters = drainWaiters
    drainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
  }
}
