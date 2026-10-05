import Database

/// Transfers a live host backing lease; release follows container shutdown.
public protocol DesignDatabaseRuntimeOwnedContainer: Sendable {
  var container: DBContainer { get }
  func release() async throws(DesignDatabaseRuntimeError)
}
