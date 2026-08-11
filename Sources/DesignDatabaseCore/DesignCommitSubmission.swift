import CircuiteFoundation

public struct DesignCommitSubmission: Sendable, Hashable, DesignDatabaseSerializable {
  public let operationID: DesignDatabaseOperationID
  public let plan: DesignMutationPlan
  public let requestDigest: ContentDigest

  public init(
    operationID: DesignDatabaseOperationID,
    plan: DesignMutationPlan,
    requestDigest: ContentDigest
  ) {
    self.operationID = operationID
    self.plan = plan
    self.requestDigest = requestDigest
  }
}
