public protocol DesignDatabaseServiceWireTransport: Sendable {
  func exchange(
    _ requestFrame: [UInt8],
    timeout: Duration
  ) async throws(DesignDatabaseServiceWireTransportError) -> [UInt8]

  func close() async throws(DesignDatabaseServiceWireTransportError)
}
