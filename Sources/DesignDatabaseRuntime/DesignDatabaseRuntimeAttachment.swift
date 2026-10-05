import CircuiteFoundation
import Database
import DesignDatabaseCore

public actor DesignDatabaseRuntimeAttachment {
  public nonisolated let locator: DesignDatabaseLocator
  public nonisolated let schemaFingerprint: ContentDigest
  public nonisolated let designSchemaBundle: DesignSchemaBundle
  public nonisolated var designSchemaBundleDigest: ContentDigest {
    designSchemaBundle.rootDigest
  }
  public nonisolated let registrationDigest: ContentDigest
  public nonisolated let contributionIDs: [DesignDatabaseRuntimeContributionID]
  public nonisolated let mutationAdapters: [
    DesignSchemaID: any DesignDatabaseRuntimeMutationAdapter
  ]
  public nonisolated let physicalWriteReclaimers: [
    String: any DesignDatabaseRuntimePhysicalWriteReclaimer
  ]
  package nonisolated let decodedProjectionPageCache: DesignProjectionDecodedPageCache
  package nonisolated let snapshotLeaseCoordinator: DesignDatabaseRuntimeLeaseCoordinator

  private let container: DBContainer
  private var isClosed = false
  private var isClosing = false
  private var containerShutdownComplete = false
  private var ownedContainer: (any DesignDatabaseRuntimeOwnedContainer)?
  private var closeWaiters: [CheckedContinuation<DesignDatabaseRuntimeTermination, Never>] = []

  package var hasExclusiveMaintenanceAuthority: Bool {
    !isClosed && ownedContainer is any DesignDatabaseRuntimeExclusiveMaintenanceContainer
  }

  package init(
    locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle,
    container: DBContainer,
    ownedContainer: (any DesignDatabaseRuntimeOwnedContainer)? = nil
  ) {
    self.locator = locator
    self.schemaFingerprint = registration.schemaFingerprint
    self.designSchemaBundle = registration.designSchemaBundle
    self.registrationDigest = registration.registrationDigest
    self.contributionIDs = registration.contributionIDs
    self.mutationAdapters = registration.mutationAdapters
    self.physicalWriteReclaimers = registration.physicalWriteReclaimers
    self.decodedProjectionPageCache = DesignProjectionDecodedPageCache()
    self.snapshotLeaseCoordinator = DesignDatabaseRuntimeLeaseCoordinator()
    self.container = container
    self.ownedContainer = ownedContainer
  }

  public func close() async -> DesignDatabaseRuntimeTermination {
    if isClosing {
      return await withCheckedContinuation { closeWaiters.append($0) }
    }
    guard !isClosed || ownedContainer != nil else { return .alreadyClosed }
    isClosing = true
    isClosed = true
    if !containerShutdownComplete {
      await snapshotLeaseCoordinator.close()
      decodedProjectionPageCache.close()
      await container.shutdown()
      containerShutdownComplete = true
    }
    let result: DesignDatabaseRuntimeTermination
    do {
      try await ownedContainer?.release()
      ownedContainer = nil
      result = .closed
    } catch { result = .cleanupFailed(reason: String(describing: error)) }
    isClosing = false
    let waiters = closeWaiters
    closeWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume(returning: result) }
    return result
  }

  package func context() throws(DesignDatabaseRuntimeError) -> DatabaseContext {
    guard !isClosed else { throw .attachmentClosed }
    return container.newContext()
  }
}
