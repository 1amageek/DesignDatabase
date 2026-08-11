import Foundation

public enum DesignDatabaseServiceStandardIOHost {
  public static func run(
    dispatcher: DesignDatabaseServiceRemoteDispatcher,
    wireCodecBudget: DesignDatabaseServiceWireCodecBudget,
    input: FileHandle = .standardInput,
    output: FileHandle = .standardOutput
  ) async throws(DesignDatabaseServiceWireTransportError)
    -> DesignDatabaseServiceStandardIOHostTermination
  {
    var iterator = input.bytes.makeAsyncIterator()
    while true {
      let requestFrame: [UInt8]?
      do {
        requestFrame = try await DesignDatabaseServiceLengthPrefixedFrameIO.read(
          from: &iterator,
          maximumFrameByteCount: wireCodecBudget.maximumFrameByteCount
        )
      } catch let error {
        try await disconnect(dispatcher, primaryError: error)
        throw error
      }
      guard let requestFrame else {
        do {
          try await dispatcher.disconnect()
        } catch let error {
          throw .protocolViolation(
            reason: "A standard-I/O service could not close disconnected sessions: \(error)"
          )
        }
        return .inputClosed
      }
      let request: DesignDatabaseServiceWireMessage
      let responseFrame: [UInt8]
      do {
        request = try DesignDatabaseServiceWireCodec.decode(
          requestFrame,
          budget: wireCodecBudget
        )
        responseFrame = try await dispatcher.dispatch(requestFrame)
      } catch let error {
        let transportError = DesignDatabaseServiceWireTransportError
          .invalidFrame(error)
        try await disconnect(dispatcher, primaryError: transportError)
        throw transportError
      }
      let encoded = try DesignDatabaseServiceLengthPrefixedFrameIO.encoded(
        responseFrame,
        maximumFrameByteCount: wireCodecBudget.maximumFrameByteCount
      )
      do {
        try output.write(contentsOf: encoded)
      } catch {
        let transportError = DesignDatabaseServiceWireTransportError
          .inputOutputFailure(reason: String(describing: error))
        try await disconnect(dispatcher, primaryError: transportError)
        throw transportError
      }
      if request.operation == .shutdown {
        return .serviceShutdown
      }
    }
  }

  private static func disconnect(
    _ dispatcher: DesignDatabaseServiceRemoteDispatcher,
    primaryError: DesignDatabaseServiceWireTransportError
  ) async throws(DesignDatabaseServiceWireTransportError) {
    do {
      try await dispatcher.disconnect()
    } catch let error {
      throw .inputOutputFailure(
        reason: "Standard-I/O transport failed with \(primaryError); session cleanup also failed with \(error)."
      )
    }
  }
}
