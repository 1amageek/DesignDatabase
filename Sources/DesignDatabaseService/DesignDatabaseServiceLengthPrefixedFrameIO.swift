import Foundation

package enum DesignDatabaseServiceLengthPrefixedFrameIO {
  package static let prefixByteCount = 8

  package static func encoded(
    _ frame: [UInt8],
    maximumFrameByteCount: UInt64
  ) throws(DesignDatabaseServiceWireTransportError) -> Data {
    guard !frame.isEmpty else {
      throw .protocolViolation(reason: "A process transport frame must not be empty.")
    }
    guard let frameByteCount = UInt64(exactly: frame.count) else {
      throw .protocolViolation(reason: "A process transport frame length overflowed.")
    }
    guard frameByteCount <= maximumFrameByteCount else {
      throw .invalidFrame(
        .budgetExceeded(
          kind: "frame bytes",
          limit: maximumFrameByteCount,
          requested: frameByteCount
        )
      )
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(prefixByteCount + frame.count)
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(
        UInt8(truncatingIfNeeded: frameByteCount >> UInt64(shift))
      )
    }
    bytes.append(contentsOf: frame)
    return Data(bytes)
  }

  package static func read(
    from iterator: inout FileHandle.AsyncBytes.Iterator,
    maximumFrameByteCount: UInt64
  ) async throws(DesignDatabaseServiceWireTransportError) -> [UInt8]? {
    var prefix: [UInt8] = []
    prefix.reserveCapacity(prefixByteCount)
    for index in 0..<prefixByteCount {
      let byte: UInt8?
      do {
        byte = try await iterator.next()
      } catch {
        throw .inputOutputFailure(reason: String(describing: error))
      }
      guard let byte else {
        if index == 0 { return nil }
        throw .inputOutputFailure(
          reason: "A process transport closed within a frame-length prefix."
        )
      }
      prefix.append(byte)
    }
    var frameByteCount: UInt64 = 0
    for byte in prefix {
      frameByteCount = (frameByteCount << 8) | UInt64(byte)
    }
    guard frameByteCount > 0 else {
      throw .protocolViolation(reason: "A process transport declared an empty frame.")
    }
    guard frameByteCount <= maximumFrameByteCount else {
      throw .invalidFrame(
        .budgetExceeded(
          kind: "frame bytes",
          limit: maximumFrameByteCount,
          requested: frameByteCount
        )
      )
    }
    guard let capacity = Int(exactly: frameByteCount) else {
      throw .protocolViolation(reason: "A process transport frame length overflowed.")
    }
    var frame: [UInt8] = []
    frame.reserveCapacity(capacity)
    for _ in 0..<capacity {
      let byte: UInt8?
      do {
        byte = try await iterator.next()
      } catch {
        throw .inputOutputFailure(reason: String(describing: error))
      }
      guard let byte else {
        throw .inputOutputFailure(
          reason: "A process transport closed within a declared frame."
        )
      }
      frame.append(byte)
    }
    return frame
  }
}
