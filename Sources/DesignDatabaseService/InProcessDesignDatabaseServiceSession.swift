import CircuiteFoundation
import DesignDatabaseCore

public actor InProcessDesignDatabaseServiceSession: DesignDatabaseServiceSession {
  public nonisolated let id: DesignDatabaseServiceSessionID
  public nonisolated let databaseID: DesignDatabaseID
  public nonisolated let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public nonisolated let featureCapabilities: DesignCapabilitySet
  public nonisolated let authorizationGrants: DesignDatabaseAuthorizationGrantSet
  public nonisolated let genesisRevision: DesignRevisionReference

  private enum State {
    case open
    case closing
    case closed
  }

  private let database: any DesignDatabaseHandle
  private let clock: ContinuousClock
  private let expiresAt: ContinuousClock.Instant
  private let maximumInFlightOperationCount: UInt64
  private var state: State = .open
  private var inFlightOperationCount: UInt64 = 0
  private var nextSnapshotID: UInt64 = 0
  private var snapshots: [
    DesignDatabaseServiceSnapshotID: any DesignReadSnapshot
  ] = [:]
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private var closeWaiters: [CheckedContinuation<Void, Never>] = []

  package init(
    id: DesignDatabaseServiceSessionID,
    database: any DesignDatabaseHandle,
    configuration: DesignDatabaseServiceSessionConfiguration
  ) {
    let clock = ContinuousClock()
    self.id = id
    self.databaseID = database.databaseID
    self.authorizationSubjectScopeID = database.authorizationSubjectScopeID
    self.featureCapabilities = database.featureCapabilities
    self.authorizationGrants = database.authorizationGrants
    self.genesisRevision = database.genesisRevision
    self.database = database
    self.clock = clock
    self.expiresAt = clock.now.advanced(by: configuration.leaseDuration)
    self.maximumInFlightOperationCount =
      configuration.maximumInFlightOperationCount
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionReference {
    try await perform { try await database.resolve(selector) }
  }

  public func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseServiceError)
    -> DesignDatabaseServiceSnapshotDescriptor {
    let snapshot = try await perform {
      try await database.openSnapshot(at: revision)
    }
    let snapshotID: DesignDatabaseServiceSnapshotID
    do {
      snapshotID = try allocateSnapshotID()
    } catch let error {
      _ = await snapshot.close()
      throw error
    }
    let descriptor: DesignDatabaseServiceSnapshotDescriptor
    do {
      descriptor = try DesignDatabaseServiceSnapshotDescriptor(
        snapshotID: snapshotID,
        revision: snapshot.revision,
        parents: snapshot.parents,
        stateDigest: snapshot.stateDigest,
        designSchemaBundle: snapshot.designSchemaBundle,
        designSchemaBundleDigest: snapshot.designSchemaBundleDigest,
        directDependencyLock: snapshot.directDependencyLock,
        dependencyRootDigest: snapshot.dependencyRootDigest,
        semanticDependencyGraphDigest: snapshot.semanticDependencyGraphDigest,
        facetRoots: snapshot.facetRoots,
        directChangeRootDigest: snapshot.directChangeRootDigest,
        projectionSemantics: snapshot.projectionSemantics,
        materializationBindings: snapshot.materializationBindings
      )
    } catch let error {
      _ = await snapshot.close()
      throw .database(error)
    }
    snapshots[snapshotID] = snapshot
    return descriptor
  }

  public func closeSnapshot(
    _ snapshotID: DesignDatabaseServiceSnapshotID
  ) async throws(DesignDatabaseServiceError) -> DesignSnapshotTermination {
    try beginOperation()
    defer { finishOperation() }
    guard let snapshot = snapshots.removeValue(forKey: snapshotID) else {
      throw .snapshotNotFound(snapshotID)
    }
    return await snapshot.close()
  }

  public func query(
    snapshotID: DesignDatabaseServiceSnapshotID,
    request: DesignQueryRequest
  ) async throws(DesignDatabaseServiceError) -> DesignQueryPage {
    try await perform {
      guard let snapshot = snapshots[snapshotID] else {
        throw DesignDatabaseServiceError.snapshotNotFound(snapshotID)
      }
      return try await snapshot.query(request)
    }
  }

  public func diff(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionDiff {
    try await perform { try await database.diff(request) }
  }

  public func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseServiceError) -> DesignDisjointMergeAssessment {
    try await perform { try await database.assessDisjointMerge(request) }
  }

  public func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseServiceError)
    -> DesignDisjointMergePublicationResult
  {
    try await perform {
      guard let publisher = database as? any DesignDisjointMergePublishing else {
        throw DesignDatabaseServiceError.operationUnavailable(
          operation: "disjoint-merge-publication"
        )
      }
      return try await publisher.publishDisjointMerge(submission)
    }
  }

  public func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError)
    -> DesignDisjointMergePublicationStatus
  {
    try await perform {
      guard let publisher = database as? any DesignDisjointMergePublishing else {
        throw DesignDatabaseServiceError.operationUnavailable(
          operation: "disjoint-merge-publication"
        )
      }
      return try await publisher.disjointMergePublicationStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseServiceError) -> DesignCommitResult {
    try await perform { try await database.submit(submission) }
  }

  public func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignCommitStatus {
    try await perform {
      try await database.commitStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateResult {
    try await perform { try await database.compareAndSetReference(request) }
  }

  public func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignReferenceUpdateStatus {
    try await perform {
      try await database.referenceStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission {
    try await perform { try await database.retain(request) }
  }

  public func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionSubmission {
    try await perform { try await database.releaseRetention(request) }
  }

  public func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseServiceError) -> DesignRevisionRetentionStatus {
    try await perform {
      try await database.retentionStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  package func shutdown() async -> DesignDatabaseServiceTermination {
    switch state {
    case .open:
      state = .closing
    case .closing:
      await withCheckedContinuation { continuation in
        closeWaiters.append(continuation)
      }
      return .alreadyClosed
    case .closed:
      return .alreadyClosed
    }
    if inFlightOperationCount > 0 {
      await withCheckedContinuation { continuation in
        drainWaiters.append(continuation)
      }
    }
    let ownedSnapshots = snapshots
      .sorted { $0.key < $1.key }
      .map(\.value)
    snapshots.removeAll(keepingCapacity: false)
    for snapshot in ownedSnapshots {
      _ = await snapshot.close()
    }
    state = .closed
    let waiters = closeWaiters
    closeWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
    return .closed
  }

  private func perform<Result: Sendable>(
    _ operation: () async throws -> Result
  ) async throws(DesignDatabaseServiceError) -> Result {
    try beginOperation()
    defer { finishOperation() }
    do {
      return try await operation()
    } catch let error as DesignDatabaseServiceError {
      throw error
    } catch let error as DesignDatabaseError {
      throw .database(error)
    } catch {
      throw .database(
        .corruption("A service operation escaped its typed contract: \(error)")
      )
    }
  }

  private func beginOperation() throws(DesignDatabaseServiceError) {
    guard state == .open else { throw .closed }
    guard clock.now < expiresAt else { throw .leaseExpired }
    guard inFlightOperationCount < maximumInFlightOperationCount else {
      throw .backpressure(limit: maximumInFlightOperationCount)
    }
    let (nextCount, overflow) = inFlightOperationCount.addingReportingOverflow(1)
    guard !overflow else { throw .identifierSpaceExhausted }
    inFlightOperationCount = nextCount
  }

  private func finishOperation() {
    precondition(inFlightOperationCount > 0)
    inFlightOperationCount -= 1
    guard state == .closing, inFlightOperationCount == 0 else { return }
    let waiters = drainWaiters
    drainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func allocateSnapshotID()
    throws(DesignDatabaseServiceError) -> DesignDatabaseServiceSnapshotID {
    let (nextID, overflow) = nextSnapshotID.addingReportingOverflow(1)
    guard !overflow else { throw .identifierSpaceExhausted }
    let result = try DesignDatabaseServiceSnapshotID(rawValue: nextID)
    nextSnapshotID = nextID
    return result
  }
}
