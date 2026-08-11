import Database
import DesignDatabaseCore

/// Supplies a prepared framework container without selecting storage inside the runtime.
///
/// Production providers keep framework security enabled and admit
/// `DesignDatabaseRuntimeStorageSecurity.administratorRole`. The runtime installs
/// that internal role only after its public grant and subject-scope checks pass.
/// Providers retain ownership of backend, path, credential, and availability
/// selection and must not expose the returned container to application callers.
public protocol DesignDatabaseRuntimeContainerProviding: Sendable {
  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer
}
