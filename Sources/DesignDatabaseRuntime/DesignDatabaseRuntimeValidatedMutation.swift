import DesignDatabaseCore

public struct DesignDatabaseRuntimeValidatedMutation: Sendable {
  public let segmentID: DesignMutationPlanSegmentID
  public let materializationPayload: [UInt8]

  public init(
    segmentID: DesignMutationPlanSegmentID,
    materializationPayload: [UInt8]
  ) {
    self.segmentID = segmentID
    self.materializationPayload = materializationPayload
  }
}
