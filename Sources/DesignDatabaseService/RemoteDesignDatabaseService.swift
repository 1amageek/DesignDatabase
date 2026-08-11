import DesignDatabaseCore

public actor RemoteDesignDatabaseService: DesignDatabaseService {
  private enum Lifecycle {
    case open
    case closing
    case closed
  }

  private let client: DesignDatabaseServiceRemoteClient
  private var sessions: [
    DesignDatabaseServiceSessionID: RemoteDesignDatabaseServiceSession
  ] = [:]
  private var lifecycle: Lifecycle = .open
  private var openingSessionCount = 0
  private var openingSessionDrainWaiters: [CheckedContinuation<Void, Never>] = []
  private var shutdownWaiters: [
    CheckedContinuation<Result<DesignDatabaseTermination, DesignDatabaseServiceError>, Never>
  ] = []

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
    openingSessionCount += 1
    defer { completeSessionOpening() }
    let descriptor: DesignDatabaseServiceRemoteSessionDescriptor = try await client.call(
      operation: .openSession,
      input: configuration
    )
    guard lifecycle == .open else {
      do {
        let _: DesignDatabaseServiceTermination = try await client.call(
          operation: .closeSession,
          input: DesignDatabaseServiceWirePayload.SessionReference(
            sessionID: descriptor.id
          )
        )
      } catch let cleanupError {
        throw .transport(
          .inputOutputFailure(
            reason: "A session opened after service admission closed and remote cleanup failed with \(cleanupError)."
          )
        )
      }
      throw .closed
    }
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
    switch lifecycle {
    case .closed:
      return .alreadyClosed
    case .closing:
      return try await waitForShutdownCompletion().get()
    case .open:
      lifecycle = .closing
    }

    await waitForSessionOpeningsToDrain()
    let outcome: Result<DesignDatabaseTermination, DesignDatabaseServiceError>
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
        outcome = .failure(.transport(
          .inputOutputFailure(
            reason: "Remote shutdown failed with \(primaryError); transport cleanup also failed with \(closeError)."
          )
        ))
        await closeOwnedSessions()
        return try completeShutdown(outcome).get()
      }
      outcome = .failure(primaryError)
      await closeOwnedSessions()
      return try completeShutdown(outcome).get()
    }
    await closeOwnedSessions()
    do {
      try await client.closeTransport()
      outcome = .success(result)
    } catch let closeError {
      outcome = .failure(closeError)
    }
    return try completeShutdown(outcome).get()
  }

  private func requireOpen() throws(DesignDatabaseServiceError) {
    guard lifecycle == .open else { throw .closed }
  }

  private func completeSessionOpening() {
    precondition(openingSessionCount > 0)
    openingSessionCount -= 1
    guard openingSessionCount == 0 else { return }
    let waiters = openingSessionDrainWaiters
    openingSessionDrainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func waitForSessionOpeningsToDrain() async {
    guard openingSessionCount > 0 else { return }
    await withCheckedContinuation { continuation in
      openingSessionDrainWaiters.append(continuation)
    }
  }

  private func waitForShutdownCompletion() async
    -> Result<DesignDatabaseTermination, DesignDatabaseServiceError>
  {
    await withCheckedContinuation { continuation in
      shutdownWaiters.append(continuation)
    }
  }

  private func closeOwnedSessions() async {
    let ownedSessions = sessions.values
    sessions.removeAll(keepingCapacity: false)
    for session in ownedSessions { await session.markClosed() }
  }

  private func completeShutdown(
    _ outcome: Result<DesignDatabaseTermination, DesignDatabaseServiceError>
  ) -> Result<DesignDatabaseTermination, DesignDatabaseServiceError> {
    lifecycle = .closed
    let waiters = shutdownWaiters
    shutdownWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume(returning: outcome) }
    return outcome
  }
}
