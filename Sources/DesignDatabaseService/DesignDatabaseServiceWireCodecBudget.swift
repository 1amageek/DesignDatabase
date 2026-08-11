public struct DesignDatabaseServiceWireCodecBudget: Sendable, Hashable {
  public let maximumFrameByteCount: UInt64
  public let maximumMetadataByteCount: UInt64
  public let maximumPayloadByteCount: UInt64

  public init(
    maximumFrameByteCount: UInt64,
    maximumMetadataByteCount: UInt64,
    maximumPayloadByteCount: UInt64
  ) throws(DesignDatabaseServiceWireCodecError) {
    guard maximumFrameByteCount > 0 else {
      throw .invalidBudget(kind: "frame bytes")
    }
    guard maximumMetadataByteCount > 0 else {
      throw .invalidBudget(kind: "metadata bytes")
    }
    guard maximumPayloadByteCount > 0 else {
      throw .invalidBudget(kind: "payload bytes")
    }
    self.maximumFrameByteCount = maximumFrameByteCount
    self.maximumMetadataByteCount = maximumMetadataByteCount
    self.maximumPayloadByteCount = maximumPayloadByteCount
  }
}
