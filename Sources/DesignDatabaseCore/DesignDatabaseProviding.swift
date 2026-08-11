public protocol DesignDatabaseProviding: Sendable {
  func create(
    _ request: DesignDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle

  func open(
    _ request: DesignDatabaseOpenRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle

  func close() async -> DesignDatabaseTermination
}
