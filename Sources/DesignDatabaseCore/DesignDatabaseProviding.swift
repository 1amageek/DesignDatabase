public protocol DesignDatabaseProviding: Sendable {
  func create(
    _ request: DesignDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabase
}
