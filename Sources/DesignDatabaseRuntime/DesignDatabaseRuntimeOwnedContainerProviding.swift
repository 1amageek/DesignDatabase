import DesignDatabaseCore

/// Optional host resource boundary; legacy providers have no maintenance authority.
public protocol DesignDatabaseRuntimeOwnedContainerProviding: DesignDatabaseRuntimeContainerProviding {
  func openOwnedContainer(for locator: DesignDatabaseLocator,
                         registration: DesignDatabaseRuntimeRegistrationBundle)
    async throws(DesignDatabaseRuntimeError) -> any DesignDatabaseRuntimeOwnedContainer
}
