import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Testing

@Suite
struct DesignMutationIdentityTests {
  @Test
  func identityPlanCanonicalizesOrderAndRejectsDuplicates() throws {
    let entityA = try DesignProvisionalEntityID(rawValue: "entity-a")
    let entityB = try DesignProvisionalEntityID(rawValue: "entity-b")
    let occurrenceA = try DesignProvisionalRelationOccurrenceID(
      rawValue: "occurrence-a"
    )
    let occurrenceB = try DesignProvisionalRelationOccurrenceID(
      rawValue: "occurrence-b"
    )

    let plan = try DesignMutationIdentityPlan(
      provisionalEntityIDs: [entityB, entityA],
      provisionalRelationOccurrenceIDs: [occurrenceB, occurrenceA]
    )

    #expect(plan.provisionalEntityIDs == [entityA, entityB])
    #expect(
      plan.provisionalRelationOccurrenceIDs == [occurrenceA, occurrenceB]
    )
    #expect(throws: DesignDatabaseError.self) {
      _ = try DesignMutationIdentityPlan(
        provisionalEntityIDs: [entityA, entityA],
        provisionalRelationOccurrenceIDs: []
      )
    }
    #expect(throws: DesignDatabaseError.self) {
      _ = try DesignMutationIdentityPlan(
        provisionalEntityIDs: [],
        provisionalRelationOccurrenceIDs: [occurrenceA, occurrenceA]
      )
    }
  }

  @Test
  func planDigestBindsEntityAndRelationOccurrenceIdentityPlans() throws {
    let entityA = try identityPlan(entity: "entity-a", occurrence: "edge-a")
    let entityB = try identityPlan(entity: "entity-b", occurrence: "edge-a")
    let occurrenceB = try identityPlan(entity: "entity-a", occurrence: "edge-b")

    let first = try planDigest(identityPlan: entityA)
    let changedEntity = try planDigest(identityPlan: entityB)
    let changedOccurrence = try planDigest(identityPlan: occurrenceB)

    #expect(DesignMutationPlanDigest.canonicalVersion == 2)
    #expect(first != changedEntity)
    #expect(first != changedOccurrence)
    #expect(changedEntity != changedOccurrence)
  }

  private func identityPlan(
    entity: String,
    occurrence: String
  ) throws -> DesignMutationIdentityPlan {
    try DesignMutationIdentityPlan(
      provisionalEntityIDs: [
        DesignProvisionalEntityID(rawValue: entity),
      ],
      provisionalRelationOccurrenceIDs: [
        DesignProvisionalRelationOccurrenceID(rawValue: occurrence),
      ]
    )
  }

  private func planDigest(
    identityPlan: DesignMutationIdentityPlan
  ) throws -> ContentDigest {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let baseRevision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 3, low: 4)
    )
    let digester = SHA256ContentDigester()
    let payload = Array("identity-payload".utf8)
    let payloadDigest = try DesignMutationPlanDigest.payload(
      payload,
      using: digester
    )
    let segment = try DesignMutationPlanSegment(
      id: DesignMutationPlanSegmentID(rawValue: "logic-import"),
      schemaID: DesignSchemaID(rawValue: "lsi.logic"),
      schemaVersion: .v1,
      adapterVersion: "1.0.0",
      targetFacet: DesignFacetID(rawValue: "logic"),
      identityPlan: identityPlan,
      payload: payload,
      payloadDigest: payloadDigest,
      expectedWriteCount: 1
    )
    let budget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1_024,
      maximumPreparedWriteCount: 1,
      maximumValidationReadCount: 1
    )
    return try DesignMutationPlanDigest.plan(
      databaseID: databaseID,
      baseRevision: baseRevision,
      designSchemaBundleDigest: digest(repeating: "1"),
      dependencyRootDigest: digest(repeating: "2"),
      semanticDependencyGraphDigest: digest(repeating: "3"),
      sourceEvidenceDigest: digest(repeating: "4"),
      budget: budget,
      segments: [segment],
      using: digester
    )
  }

  private func digest(repeating character: Character) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: character, count: 64)
    )
  }
}
