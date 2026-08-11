public struct DesignMutationPlanBudget: Sendable, Hashable, DesignDatabaseSerializable {
  public let maximumSegmentCount: UInt32
  public let maximumPayloadByteCount: UInt64
  public let maximumPreparedWriteCount: UInt64
  public let maximumValidationReadCount: UInt64

  public init(
    maximumSegmentCount: UInt32,
    maximumPayloadByteCount: UInt64,
    maximumPreparedWriteCount: UInt64,
    maximumValidationReadCount: UInt64
  ) throws(DesignDatabaseError) {
    guard maximumSegmentCount > 0,
          maximumPayloadByteCount > 0,
          maximumPreparedWriteCount > 0,
          maximumValidationReadCount > 0 else {
      throw .invalidMutationPlan(
        reason: "Every mutation-plan budget must be greater than zero."
      )
    }
    self.maximumSegmentCount = maximumSegmentCount
    self.maximumPayloadByteCount = maximumPayloadByteCount
    self.maximumPreparedWriteCount = maximumPreparedWriteCount
    self.maximumValidationReadCount = maximumValidationReadCount
  }
}
