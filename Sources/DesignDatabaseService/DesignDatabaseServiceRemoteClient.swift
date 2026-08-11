import DesignDatabaseCore
import Foundation

package actor DesignDatabaseServiceRemoteClient {
  private let transport: any DesignDatabaseServiceWireTransport
  private let configuration: DesignDatabaseServiceRemoteConfiguration
  private var nextRequestID: UInt64 = 0
  private var isClosed = false

  package init(
    transport: any DesignDatabaseServiceWireTransport,
    configuration: DesignDatabaseServiceRemoteConfiguration
  ) {
    self.transport = transport
    self.configuration = configuration
  }

  package func call<Input, Output>(
    operation: DesignDatabaseServiceWireOperation,
    input: Input,
    expecting outputType: Output.Type = Output.self
  ) async throws(DesignDatabaseServiceError) -> Output
  where Input: Sendable & Encodable, Output: Sendable & Decodable {
    let response = try await exchange(operation: operation, input: input)
    guard response.payloadFormat == .json else {
      throw .transport(
        .protocolViolation(
          reason: "A remote service JSON operation returned another payload format."
        )
      )
    }
    return try decode(Output.self, from: response.payload)
  }

  package func query(
    _ input: DesignDatabaseServiceWirePayload.Query
  ) async throws(DesignDatabaseServiceError) -> DesignQueryPage {
    let response = try await exchange(operation: .query, input: input)
    guard response.payloadFormat == .queryPageV1 else {
      throw .transport(
        .protocolViolation(
          reason: "A remote semantic query did not return a binary query-page payload."
        )
      )
    }
    do {
      return try DesignDatabaseServiceQueryPageCodec.decode(
        response.payload,
        budget: configuration.queryPageCodecBudget
      )
    } catch let error {
      throw .transport(
        .protocolViolation(
          reason: "A remote semantic query page is invalid: \(error)"
        )
      )
    }
  }

  package func closeTransport() async throws(DesignDatabaseServiceError) {
    guard !isClosed else { return }
    isClosed = true
    do {
      try await transport.close()
    } catch let error {
      isClosed = false
      throw .transport(error)
    }
  }

  private func exchange<Input>(
    operation: DesignDatabaseServiceWireOperation,
    input: Input
  ) async throws(DesignDatabaseServiceError) -> DesignDatabaseServiceWireMessage
  where Input: Sendable & Encodable {
    guard !isClosed else { throw .transport(.closed) }
    let requestID = try allocateRequestID()
    let payload = try encode(input)
    let request: DesignDatabaseServiceWireMessage
    let requestFrame: [UInt8]
    do {
      request = try DesignDatabaseServiceWireMessage(
        requestID: requestID,
        operation: operation,
        kind: .request,
        payloadFormat: .json,
        payload: payload
      )
      requestFrame = try DesignDatabaseServiceWireCodec.encode(
        request,
        budget: configuration.wireCodecBudget
      )
    } catch let error {
      throw .transport(.invalidFrame(error))
    }
    let responseFrame: [UInt8]
    do {
      responseFrame = try await transport.exchange(
        requestFrame,
        timeout: configuration.requestTimeout
      )
    } catch let error {
      throw .transport(error)
    }
    let response: DesignDatabaseServiceWireMessage
    do {
      response = try DesignDatabaseServiceWireCodec.decode(
        responseFrame,
        budget: configuration.wireCodecBudget
      )
    } catch let error {
      throw .transport(.invalidFrame(error))
    }
    guard response.requestID == requestID,
          response.operation == operation else {
      throw .transport(
        .protocolViolation(
          reason: "A remote service response does not match its request identity."
        )
      )
    }
    switch response.kind {
    case .success:
      return response
    case .failure:
      guard response.payloadFormat == .json else {
        throw .transport(
          .protocolViolation(
            reason: "A remote service failure did not use typed JSON."
          )
        )
      }
      throw try decode(
        DesignDatabaseServiceError.self,
        from: response.payload
      )
    case .request:
      throw .transport(
        .protocolViolation(reason: "A remote service returned a request frame.")
      )
    }
  }

  private func allocateRequestID()
    throws(DesignDatabaseServiceError) -> UInt64 {
    let (next, overflow) = nextRequestID.addingReportingOverflow(1)
    guard !overflow, next > 0 else {
      throw .transport(
        .protocolViolation(reason: "The remote request ID space is exhausted.")
      )
    }
    nextRequestID = next
    return next
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
    from bytes: [UInt8]
  ) throws(DesignDatabaseServiceError) -> Value {
    do {
      return try JSONDecoder().decode(type, from: Data(bytes))
    } catch {
      throw .transport(
        .serializationFailure(reason: String(describing: error))
      )
    }
  }
}
