import DesignDatabaseCore

public protocol DesignDatabaseService: Sendable {
  func negotiate(
    _ request: DesignServiceNegotiationRequest
  ) async throws(DesignDatabaseServiceError) -> DesignServiceNegotiationResult

  func openSession(
    configuration: DesignDatabaseServiceSessionConfiguration
  ) async throws(DesignDatabaseServiceError) -> any DesignDatabaseServiceSession

  func closeSession(
    _ sessionID: DesignDatabaseServiceSessionID
  ) async throws(DesignDatabaseServiceError) -> DesignDatabaseServiceTermination

  func shutdown() async throws(DesignDatabaseServiceError)
    -> DesignDatabaseTermination
}
