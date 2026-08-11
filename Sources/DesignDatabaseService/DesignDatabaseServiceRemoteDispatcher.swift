import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public actor DesignDatabaseServiceRemoteDispatcher {
  private let service: any DesignDatabaseService
  private let subjectContext: DesignDatabaseServiceAuthenticatedSubjectContext
  private let configuration: DesignDatabaseServiceRemoteConfiguration
  private var sessions: [
    DesignDatabaseServiceSessionID: any DesignDatabaseServiceSession
  ] = [:]
  private var isShutdown = false

  public init(
    service: any DesignDatabaseService,
    subjectContext: DesignDatabaseServiceAuthenticatedSubjectContext,
    configuration: DesignDatabaseServiceRemoteConfiguration
  ) {
    self.service = service
    self.subjectContext = subjectContext
    self.configuration = configuration
  }

  public func dispatch(
    _ requestFrame: [UInt8]
  ) async throws(DesignDatabaseServiceWireCodecError) -> [UInt8] {
    let request = try DesignDatabaseServiceWireCodec.decode(
      requestFrame,
      budget: configuration.wireCodecBudget
    )
    let response: DesignDatabaseServiceWireMessage
    do {
      guard request.kind == .request, request.payloadFormat == .json else {
        throw DesignDatabaseServiceError.transport(
          .protocolViolation(
            reason: "A remote dispatcher accepts only JSON request frames."
          )
        )
      }
      guard !isShutdown || request.operation == .shutdown else {
        throw DesignDatabaseServiceError.closed
      }
      response = try await execute(request)
    } catch let error as DesignDatabaseServiceError {
      response = try failureResponse(for: request, error: error)
    } catch {
      response = try failureResponse(
        for: request,
        error: .transport(
          .protocolViolation(
            reason: "A remote dispatch operation escaped its typed contract: \(error)"
          )
        )
      )
    }
    return try DesignDatabaseServiceWireCodec.encode(
      response,
      budget: configuration.wireCodecBudget
    )
  }

  public func disconnect() async throws(DesignDatabaseServiceError) {
    let ownedSessionIDs = sessions.keys.sorted()
    var failures: [String] = []
    for sessionID in ownedSessionIDs {
      do {
        _ = try await service.closeSession(sessionID)
        sessions.removeValue(forKey: sessionID)
      } catch let error {
        failures.append("session \(sessionID.rawValue): \(error)")
      }
    }
    guard failures.isEmpty else {
      throw .transport(
        .inputOutputFailure(
          reason: "Remote disconnect could not close every owned session: \(failures.joined(separator: "; "))."
        )
      )
    }
  }

  private func execute(
    _ request: DesignDatabaseServiceWireMessage
  ) async throws(DesignDatabaseServiceError) -> DesignDatabaseServiceWireMessage {
    switch request.operation {
    case .negotiate:
      let input = try decode(
        DesignServiceNegotiationRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await service.negotiate(input)
      )
    case .openSession:
      let input = try decode(
        DesignDatabaseServiceSessionConfiguration.self,
        from: request.payload
      )
      let session = try await service.openSession(configuration: input)
      guard session.authorizationSubjectScopeID
              == subjectContext.authorizationSubjectScopeID else {
        do {
          _ = try await service.closeSession(session.id)
        } catch let error {
          throw error
        }
        throw .transport(
          .protocolViolation(
            reason: "The service opened a session for another authenticated subject scope."
          )
        )
      }
      guard sessions[session.id] == nil else {
        do {
          _ = try await service.closeSession(session.id)
        } catch let error {
          throw error
        }
        throw .transport(
          .protocolViolation(reason: "The service reused an active session ID.")
        )
      }
      let descriptor: DesignDatabaseServiceRemoteSessionDescriptor
      do {
        descriptor = try DesignDatabaseServiceRemoteSessionDescriptor(
          id: session.id,
          databaseID: session.databaseID,
          authorizationSubjectScopeID: session.authorizationSubjectScopeID,
          featureCapabilities: session.featureCapabilities,
          authorizationGrants: session.authorizationGrants,
          genesisRevision: session.genesisRevision
        )
      } catch let error {
        throw .transport(error)
      }
      sessions[session.id] = session
      return try successResponse(for: request, value: descriptor)
    case .closeSession:
      let input = try decode(
        DesignDatabaseServiceWirePayload.SessionReference.self,
        from: request.payload
      )
      _ = try session(input.sessionID)
      let result = try await service.closeSession(input.sessionID)
      sessions.removeValue(forKey: input.sessionID)
      return try successResponse(for: request, value: result)
    case .shutdown:
      _ = try decode(
        DesignDatabaseServiceWirePayload.Empty.self,
        from: request.payload
      )
      guard subjectContext.serviceShutdownAuthorized else {
        throw .database(
          .unauthorized(
            grant: .administer,
            subjectScopeID: subjectContext.authorizationSubjectScopeID
          )
        )
      }
      let result = try await service.shutdown()
      sessions.removeAll(keepingCapacity: false)
      isShutdown = true
      return try successResponse(for: request, value: result)
    case .resolve:
      let input = try decode(
        DesignDatabaseServiceWirePayload.SessionValue<DesignRevisionSelector>.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).resolve(input.value)
      )
    case .openSnapshot:
      let input = try decode(
        DesignDatabaseServiceWirePayload.OpenSnapshot.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).openSnapshot(
          at: input.revision
        )
      )
    case .closeSnapshot:
      let input = try decode(
        DesignDatabaseServiceWirePayload.CloseSnapshot.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).closeSnapshot(
          input.snapshotID
        )
      )
    case .query:
      let input = try decode(
        DesignDatabaseServiceWirePayload.Query.self,
        from: request.payload
      )
      let page = try await session(input.sessionID).query(
        snapshotID: input.snapshotID,
        request: input.request
      )
      let payload: [UInt8]
      do {
        payload = try DesignDatabaseServiceQueryPageCodec.encode(
          page,
          budget: configuration.queryPageCodecBudget
        )
      } catch let error {
        throw .transport(
          .protocolViolation(
            reason: "The service could not encode a semantic query page: \(error)"
          )
        )
      }
      return try wireMessage(
        for: request,
        kind: .success,
        payloadFormat: .queryPageV1,
        payload: payload
      )
    case .diff:
      let input = try decodeSessionValue(
        DesignRevisionDiffRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).diff(input.value)
      )
    case .assessDisjointMerge:
      let input = try decodeSessionValue(
        DesignDisjointMergeRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).assessDisjointMerge(
          input.value
        )
      )
    case .publishDisjointMerge:
      let input = try decodeSessionValue(
        DesignDisjointMergePublicationSubmission.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).publishDisjointMerge(
          input.value
        )
      )
    case .disjointMergePublicationStatus:
      let input = try decodeStatus(from: request.payload)
      return try successResponse(
        for: request,
        value: try await session(input.sessionID)
          .disjointMergePublicationStatus(
            operation: input.operation,
            requestDigest: input.requestDigest
          )
      )
    case .submit:
      let input = try decodeSessionValue(
        DesignCommitSubmission.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).submit(input.value)
      )
    case .commitStatus:
      let input = try decodeStatus(from: request.payload)
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).commitStatus(
          operation: input.operation,
          requestDigest: input.requestDigest
        )
      )
    case .compareAndSetReference:
      let input = try decodeSessionValue(
        DesignReferenceUpdateRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).compareAndSetReference(
          input.value
        )
      )
    case .referenceStatus:
      let input = try decodeStatus(from: request.payload)
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).referenceStatus(
          operation: input.operation,
          requestDigest: input.requestDigest
        )
      )
    case .retain:
      let input = try decodeSessionValue(
        DesignRevisionRetentionRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).retain(input.value)
      )
    case .releaseRetention:
      let input = try decodeSessionValue(
        DesignRevisionRetentionReleaseRequest.self,
        from: request.payload
      )
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).releaseRetention(input.value)
      )
    case .retentionStatus:
      let input = try decodeStatus(from: request.payload)
      return try successResponse(
        for: request,
        value: try await session(input.sessionID).retentionStatus(
          operation: input.operation,
          requestDigest: input.requestDigest
        )
      )
    }
  }

  private func session(
    _ id: DesignDatabaseServiceSessionID
  ) throws(DesignDatabaseServiceError) -> any DesignDatabaseServiceSession {
    guard let session = sessions[id] else { throw .closed }
    guard session.authorizationSubjectScopeID
            == subjectContext.authorizationSubjectScopeID else {
      throw .transport(
        .protocolViolation(
          reason: "A remote session crossed its authenticated subject scope."
        )
      )
    }
    return session
  }

  private func decodeSessionValue<Value>(
    _ type: Value.Type,
    from payload: [UInt8]
  ) throws(DesignDatabaseServiceError)
    -> DesignDatabaseServiceWirePayload.SessionValue<Value>
  where Value: Sendable & Codable {
    try decode(
      DesignDatabaseServiceWirePayload.SessionValue<Value>.self,
      from: payload
    )
  }

  private func decodeStatus(
    from payload: [UInt8]
  ) throws(DesignDatabaseServiceError)
    -> DesignDatabaseServiceWirePayload.OperationStatus
  {
    try decode(
      DesignDatabaseServiceWirePayload.OperationStatus.self,
      from: payload
    )
  }

  private func successResponse<Value: Encodable>(
    for request: DesignDatabaseServiceWireMessage,
    value: Value
  ) throws(DesignDatabaseServiceError) -> DesignDatabaseServiceWireMessage {
    try wireMessage(
      for: request,
      kind: .success,
      payloadFormat: .json,
      payload: try encode(value)
    )
  }

  private func failureResponse(
    for request: DesignDatabaseServiceWireMessage,
    error: DesignDatabaseServiceError
  ) throws(DesignDatabaseServiceWireCodecError)
    -> DesignDatabaseServiceWireMessage
  {
    let payload: [UInt8]
    do {
      payload = try encode(error)
    } catch let serviceError {
      throw .invalidMessage(reason: String(describing: serviceError))
    }
    return try DesignDatabaseServiceWireMessage(
      requestID: request.requestID,
      operation: request.operation,
      kind: .failure,
      payloadFormat: .json,
      payload: payload
    )
  }

  private func wireMessage(
    for request: DesignDatabaseServiceWireMessage,
    kind: DesignDatabaseServiceWireMessage.Kind,
    payloadFormat: DesignDatabaseServiceWireMessage.PayloadFormat,
    payload: [UInt8]
  ) throws(DesignDatabaseServiceError) -> DesignDatabaseServiceWireMessage {
    do {
      return try DesignDatabaseServiceWireMessage(
        requestID: request.requestID,
        operation: request.operation,
        kind: kind,
        payloadFormat: payloadFormat,
        payload: payload
      )
    } catch let error {
      throw .transport(.invalidFrame(error))
    }
  }

  private func encode<Value: Encodable>(
    _ value: Value
  ) throws(DesignDatabaseServiceError) -> [UInt8] {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return Array(try encoder.encode(value))
    } catch {
      throw .transport(
        .serializationFailure(reason: String(describing: error))
      )
    }
  }

  private func decode<Value: Decodable>(
    _ type: Value.Type,
    from payload: [UInt8]
  ) throws(DesignDatabaseServiceError) -> Value {
    do {
      return try JSONDecoder().decode(type, from: Data(payload))
    } catch {
      throw .transport(
        .serializationFailure(reason: String(describing: error))
      )
    }
  }
}
