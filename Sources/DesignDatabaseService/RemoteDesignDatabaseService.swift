import DesignDatabaseCore

public actor RemoteDesignDatabaseService: DesignDatabaseService {
  private let client: DesignDatabaseServiceRemoteClient
  private var sessions: [
    DesignDatabaseServiceSessionID: RemoteDesignDatabaseServiceSession
  ] = [:]
  private var isShutdown = false

  public init(
    transport: any DesignDatabaseServiceWireTransport,
    configuration: DesignDatabaseServiceRemoteConfiguration
  ) {
    client = DesignDatabaseServiceRemoteClient(
      transport: transport,
      configuration: configuration
    )
  }

  public func negotiate(
    _ request: DesignServiceNegotiationRequest
  ) async throws(DesignDatabaseServiceError) -> DesignServiceNegotiationResult {
    try requireOpen()
    return try await client.call(operation: .negotiate, input: request)
  }

  public func openSession(
    configuration: DesignDatabaseServiceSessionConfiguration
  ) async throws(DesignDatabaseServiceError) -> any DesignDatabaseServiceSession {
    try requireOpen()
    let descriptor: DesignDatabaseServiceRemoteSessionDescriptor = try await client.call(
      operation: .openSession,
      input: configuration
    )
    guard sessions[descriptor.id] == nil else {
      throw .transport(
        .protocolViolation(reason: "A remote service reused an active session ID.")
      )
    }
    let session = RemoteDesignDatabaseServiceSession(
      descriptor: descriptor,
      client: client
    )
    sessions[descriptor.id] = session
    return session
  }

  public func closeSession(
    _ sessionID: DesignDatabaseServiceSessionID
  ) async throws(DesignDatabaseServiceError) -> DesignDatabaseServiceTermination {
    try requireOpen()
    let result: DesignDatabaseServiceTermination = try await client.call(
      operation: .closeSession,
      input: DesignDatabaseServiceWirePayload.SessionReference(
        sessionID: sessionID
      )
    )
    if let session = sessions.removeValue(forKey: sessionID) {
      await session.markClosed()
    }
    return result
  }

  public func shutdown()
    async throws(DesignDatabaseServiceError) -> DesignDatabaseTermination {
    guard !isShutdown else { return .alreadyClosed }
    let result: DesignDatabaseTermination
    do {
      result = try await client.call(
        operation: .shutdown,
        input: DesignDatabaseServiceWirePayload.Empty()
      )
    } catch let primaryError {
      do {
        try await client.closeTransport()
      } catch let closeError {
        throw .transport(
          .inputOutputFailure(
            reason: "Remote shutdown failed with \(primaryError); transport cleanup also failed with \(closeError)."
          )
        )
      }
      throw primaryError
    }
    isShutdown = true
    let ownedSessions = sessions.values
    sessions.removeAll(keepingCapacity: false)
    for session in ownedSessions { await session.markClosed() }
    try await client.closeTransport()
    return result
  }

  private func requireOpen() throws(DesignDatabaseServiceError) {
    guard !isShutdown else { throw .closed }
  }
}
