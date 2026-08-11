public struct DesignDatabaseServiceQueryPageCodecBudget:
  Sendable,
  Hashable
{
  public let maximumFrameByteCount: UInt64
  public let maximumMetadataByteCount: UInt64
  public let maximumRowCount: UInt64

  public init(
    maximumFrameByteCount: UInt64,
    maximumMetadataByteCount: UInt64,
    maximumRowCount: UInt64
  ) throws(DesignDatabaseServiceQueryPageCodecError) {
    guard maximumFrameByteCount > 0 else {
      throw .invalidBudget(kind: "frame bytes")
    }
    guard maximumMetadataByteCount > 0 else {
      throw .invalidBudget(kind: "metadata bytes")
    }
    guard maximumRowCount > 0 else {
      throw .invalidBudget(kind: "row count")
    }
    self.maximumFrameByteCount = maximumFrameByteCount
    self.maximumMetadataByteCount = maximumMetadataByteCount
    self.maximumRowCount = maximumRowCount
  }
}
