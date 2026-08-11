import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum DesignDatabaseServiceWireCodec {
  public static let currentVersion: UInt16 = 1

  private static let magic: [UInt8] = [0x44, 0x44, 0x42, 0x53]
  private static let headerByteCount: UInt64 = 24

  public static func encode(
    _ message: DesignDatabaseServiceWireMessage,
    budget: DesignDatabaseServiceWireCodecBudget,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) throws(DesignDatabaseServiceWireCodecError) -> [UInt8] {
    let payloadCount = try exactUInt64(message.payload.count)
    try requireWithinBudget(
      kind: "payload bytes",
      requested: payloadCount,
      limit: budget.maximumPayloadByteCount
    )
    let payloadDigest = try digest(message.payload, using: digester)
    let metadata = Metadata(message: message, payloadDigest: payloadDigest)
    let metadataBytes: [UInt8]
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      metadataBytes = Array(try encoder.encode(metadata))
    } catch {
      throw .invalidMetadata(reason: String(describing: error))
    }
    let metadataCount = try exactUInt64(metadataBytes.count)
    try requireWithinBudget(
      kind: "metadata bytes",
      requested: metadataCount,
      limit: budget.maximumMetadataByteCount
    )
    let frameByteCount = try adding(
      try adding(headerByteCount, metadataCount),
      payloadCount
    )
    try requireWithinBudget(
      kind: "frame bytes",
      requested: frameByteCount,
      limit: budget.maximumFrameByteCount
    )
    guard let capacity = Int(exactly: frameByteCount) else {
      throw .integerOverflow
    }

    var frame: [UInt8] = []
    frame.reserveCapacity(capacity)
    frame.append(contentsOf: magic)
    append(currentVersion, to: &frame)
    append(UInt16(0), to: &frame)
    append(metadataCount, to: &frame)
    append(payloadCount, to: &frame)
    frame.append(contentsOf: metadataBytes)
    frame.append(contentsOf: message.payload)
    guard frame.count == capacity else { throw .integerOverflow }
    return frame
  }

  public static func decode(
    _ frame: [UInt8],
    budget: DesignDatabaseServiceWireCodecBudget,
    digester: any ContentDigesting = SHA256ContentDigester()
  ) throws(DesignDatabaseServiceWireCodecError)
    -> DesignDatabaseServiceWireMessage
  {
    let frameByteCount = try exactUInt64(frame.count)
    try requireWithinBudget(
      kind: "frame bytes",
      requested: frameByteCount,
      limit: budget.maximumFrameByteCount
    )
    var cursor = Cursor(bytes: frame)
    guard try cursor.read(count: magic.count) == magic else {
      throw .invalidMagic
    }
    let version = try cursor.readUInt16()
    guard version == currentVersion else { throw .unsupportedVersion(version) }
    let flags = try cursor.readUInt16()
    guard flags == 0 else { throw .unsupportedFlags(flags) }
    let metadataCount = try cursor.readUInt64()
    let payloadCount = try cursor.readUInt64()
    try requireWithinBudget(
      kind: "metadata bytes",
      requested: metadataCount,
      limit: budget.maximumMetadataByteCount
    )
    try requireWithinBudget(
      kind: "payload bytes",
      requested: payloadCount,
      limit: budget.maximumPayloadByteCount
    )
    guard let metadataLength = Int(exactly: metadataCount),
          let payloadLength = Int(exactly: payloadCount) else {
      throw .integerOverflow
    }
    let metadataBytes = try cursor.read(count: metadataLength)
    let payload = try cursor.read(count: payloadLength)
    guard cursor.remainingByteCount == 0 else {
      throw .trailingBytes(try exactUInt64(cursor.remainingByteCount))
    }
    let metadata: Metadata
    do {
      metadata = try JSONDecoder().decode(
        Metadata.self,
        from: Data(metadataBytes)
      )
    } catch {
      throw .invalidMetadata(reason: String(describing: error))
    }
    let actualDigest = try digest(payload, using: digester)
    guard actualDigest == metadata.payloadDigest else {
      throw .payloadDigestMismatch(
        expected: metadata.payloadDigest,
        actual: actualDigest
      )
    }
    return try DesignDatabaseServiceWireMessage(
      requestID: metadata.requestID,
      operation: metadata.operation,
      kind: metadata.kind,
      payloadFormat: metadata.payloadFormat,
      payload: payload
    )
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseServiceWireCodecError) -> ContentDigest {
    do {
      let byteCount = UInt64(bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(byteCount, 1),
        maximumTotalByteCount: max(byteCount, 1),
        maximumUpdateCount: 1
      )
      return try digester.digest(using: .sha256, limits: limits) {
        (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(bytes)
      }.digest
    } catch {
      throw .digestFailure(reason: String(describing: error))
    }
  }

  private static func requireWithinBudget(
    kind: String,
    requested: UInt64,
    limit: UInt64
  ) throws(DesignDatabaseServiceWireCodecError) {
    guard requested <= limit else {
      throw .budgetExceeded(kind: kind, limit: limit, requested: requested)
    }
  }

  private static func exactUInt64(
    _ value: Int
  ) throws(DesignDatabaseServiceWireCodecError) -> UInt64 {
    guard let result = UInt64(exactly: value) else { throw .integerOverflow }
    return result
  }

  private static func adding(
    _ lhs: UInt64,
    _ rhs: UInt64
  ) throws(DesignDatabaseServiceWireCodecError) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw .integerOverflow }
    return result
  }

  private static func append(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  private static func append(_ value: UInt64, to bytes: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }
}

private extension DesignDatabaseServiceWireCodec {
  struct Metadata: Codable {
    let requestID: UInt64
    let operation: DesignDatabaseServiceWireOperation
    let kind: DesignDatabaseServiceWireMessage.Kind
    let payloadFormat: DesignDatabaseServiceWireMessage.PayloadFormat
    let payloadDigest: ContentDigest

    init(
      message: DesignDatabaseServiceWireMessage,
      payloadDigest: ContentDigest
    ) {
      requestID = message.requestID
      operation = message.operation
      kind = message.kind
      payloadFormat = message.payloadFormat
      self.payloadDigest = payloadDigest
    }
  }

  struct Cursor {
    let bytes: [UInt8]
    private(set) var offset = 0

    var remainingByteCount: Int { bytes.count - offset }

    mutating func read(
      count: Int
    ) throws(DesignDatabaseServiceWireCodecError) -> [UInt8] {
      guard count >= 0, count <= remainingByteCount else { throw .truncated }
      let end = offset + count
      let result = Array(bytes[offset..<end])
      offset = end
      return result
    }

    mutating func readUInt16()
      throws(DesignDatabaseServiceWireCodecError) -> UInt16 {
      let value = try read(count: 2)
      return (UInt16(value[0]) << 8) | UInt16(value[1])
    }

    mutating func readUInt64()
      throws(DesignDatabaseServiceWireCodecError) -> UInt64 {
      let value = try read(count: 8)
      var result: UInt64 = 0
      for byte in value { result = (result << 8) | UInt64(byte) }
      return result
    }
  }
}
