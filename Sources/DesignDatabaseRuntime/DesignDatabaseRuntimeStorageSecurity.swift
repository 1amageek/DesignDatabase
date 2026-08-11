import Database
import DesignDatabaseCore

/// The container-level authority used exclusively inside DesignDatabaseRuntime.
///
/// A host provider keeps framework security enabled and admits this role as an
/// administrator. DesignDatabaseRuntime installs the matching TaskLocal principal
/// only around calls that have already passed the public handle's typed grant and
/// subject-scope authorization checks.
public enum DesignDatabaseRuntimeStorageSecurity {
  public static let administratorRole =
    "lsi.design-database-runtime.storage-administrator"

  package static let authorizationContext = AuthorizationContext.authenticated(
    Principal(
      identifier: "lsi.design-database-runtime",
      roles: [administratorRole]
    )
  )

  package nonisolated(nonsending) static func withAuthorizedDatabaseAccess<Result>(
    _ operation: () async throws(DesignDatabaseError) -> Result
  ) async throws(DesignDatabaseError) -> Result {
    do {
      return try await RequestAuthorization.$context.withValue(
        authorizationContext
      ) {
        try await operation()
      }
    } catch let failure as DesignDatabaseError {
      throw failure
    } catch {
      throw .corruption(
        "Task-local storage authorization produced an unexpected failure: \(error)"
      )
    }
  }

  package nonisolated(nonsending) static func withAuthorizedAccess<Result>(
    _ operation: nonisolated(nonsending) () async throws -> Result
  ) async rethrows -> Result {
    try await RequestAuthorization.$context.withValue(
      authorizationContext,
      operation: operation
    )
  }

  package nonisolated(nonsending) static func withUnprivilegedAccess<Result>(
    _ operation: nonisolated(nonsending) () async throws -> Result
  ) async rethrows -> Result {
    try await RequestAuthorization.$context.withValue(
      .anonymous,
      operation: operation
    )
  }

  package static func withUnprivilegedAccess<Result>(
    _ operation: () throws -> Result
  ) rethrows -> Result {
    try RequestAuthorization.$context.withValue(
      .anonymous,
      operation: operation
    )
  }
}
