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

  package init(
    locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle,
    container: DBContainer
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
  }

  public func close() async -> DesignDatabaseRuntimeTermination {
    guard !isClosed else { return .alreadyClosed }
    isClosed = true
    await snapshotLeaseCoordinator.close()
    decodedProjectionPageCache.close()
    await container.shutdown()
    return .closed
  }

  package func context() throws(DesignDatabaseRuntimeError) -> DatabaseContext {
    guard !isClosed else { throw .attachmentClosed }
    return container.newContext()
  }
}
