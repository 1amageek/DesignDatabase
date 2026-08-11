import CircuiteFoundation

public struct DesignMutationPlanSegment: Sendable, Hashable, DesignDatabaseSerializable {
  public let id: DesignMutationPlanSegmentID
  public let schemaID: DesignSchemaID
  public let schemaVersion: SchemaVersion
  public let adapterVersion: String
  public let targetFacet: DesignFacetID
  public let identityPlan: DesignMutationIdentityPlan
  public let payload: [UInt8]
  public let payloadDigest: ContentDigest
  public let expectedWriteCount: UInt64

  public init(
    id: DesignMutationPlanSegmentID,
    schemaID: DesignSchemaID,
    schemaVersion: SchemaVersion,
    adapterVersion: String,
    targetFacet: DesignFacetID,
    identityPlan: DesignMutationIdentityPlan = DesignMutationIdentityPlan(),
    payload: [UInt8],
    payloadDigest: ContentDigest,
    expectedWriteCount: UInt64
  ) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(
      adapterVersion,
      kind: "Design mutation adapter version"
    )
    guard !payload.isEmpty else {
      throw .invalidMutationPlan(
        reason: "A mutation-plan segment payload must not be empty."
      )
    }
    guard expectedWriteCount > 0 else {
      throw .invalidMutationPlan(
        reason: "A mutation-plan segment must declare at least one expected write."
      )
    }
    self.id = id
    self.schemaID = schemaID
    self.schemaVersion = schemaVersion
    self.adapterVersion = adapterVersion
    self.targetFacet = targetFacet
    self.identityPlan = identityPlan
    self.payload = payload
    self.payloadDigest = payloadDigest
    self.expectedWriteCount = expectedWriteCount
  }
}
