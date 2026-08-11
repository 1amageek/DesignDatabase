public struct DesignQueryResourceReport: Sendable, Hashable, DesignDatabaseSerializable {
  public let resultCount: UInt64
  public let nodeFetchCount: UInt64
  public let encodedReadByteCount: UInt64
  public let decodedByteCount: UInt64
  public let outputByteCount: UInt64
  public let workCount: UInt64

  public init(
    resultCount: UInt64 = 0,
    nodeFetchCount: UInt64 = 0,
    encodedReadByteCount: UInt64 = 0,
    decodedByteCount: UInt64 = 0,
    outputByteCount: UInt64 = 0,
    workCount: UInt64 = 0
  ) {
    self.resultCount = resultCount
    self.nodeFetchCount = nodeFetchCount
    self.encodedReadByteCount = encodedReadByteCount
    self.decodedByteCount = decodedByteCount
    self.outputByteCount = outputByteCount
    self.workCount = workCount
  }
}
