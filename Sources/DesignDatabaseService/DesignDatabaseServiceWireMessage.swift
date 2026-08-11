public struct DesignDatabaseServiceWireMessage: Sendable, Hashable {
  public enum Kind: String, Sendable, Hashable, Codable {
    case request
    case success
    case failure
  }

  public enum PayloadFormat: String, Sendable, Hashable, Codable {
    case json
    case queryPageV1 = "query-page-v1"
  }

  public let requestID: UInt64
  public let operation: DesignDatabaseServiceWireOperation
  public let kind: Kind
  public let payloadFormat: PayloadFormat
  public let payload: [UInt8]

  public init(
    requestID: UInt64,
    operation: DesignDatabaseServiceWireOperation,
    kind: Kind,
    payloadFormat: PayloadFormat,
    payload: [UInt8]
  ) throws(DesignDatabaseServiceWireCodecError) {
    guard requestID > 0 else {
      throw .invalidMessage(reason: "A service wire request ID must be nonzero.")
    }
    guard !payload.isEmpty else {
      throw .invalidMessage(reason: "A service wire payload must not be empty.")
    }
    if payloadFormat == .queryPageV1 {
      guard operation == .query, kind == .success else {
        throw .invalidMessage(
          reason: "A binary query-page payload is valid only for a successful query response."
        )
      }
    }
    if kind == .failure, payloadFormat != .json {
      throw .invalidMessage(reason: "A service wire failure must use typed JSON.")
    }
    self.requestID = requestID
    self.operation = operation
    self.kind = kind
    self.payloadFormat = payloadFormat
    self.payload = payload
  }
}
