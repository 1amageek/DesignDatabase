import CircuiteFoundation
import DesignDatabaseCore
import DesignDatabaseRuntime
import Testing

@Suite("Projection relation change validation")
struct DesignProjectionRelationChangeValidatorTests {
  @Test("Insertion requires one reserved identity and both directional entries")
  func insertionRequiresReservedIdentityAndCompletePair() throws {
    let segmentID = try DesignMutationPlanSegmentID(rawValue: "relation-insert")
    let record = try relation(
      occurrence: 1,
      target: 2,
      order: 1
    )
    let entries = try record.projectionEntries()
    let mutation = DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges(
      segmentID: segmentID,
      changes: try entries.map {
        try DesignProjectionChange(
          family: .connectivity,
          before: nil,
          after: $0
        )
      }
    )
    let assignments = try DesignMutationIdentityAssignments(
      entities: [],
      relationOccurrences: [
        DesignRelationOccurrenceIdentityAssignment(
          provisionalID: try DesignProvisionalRelationOccurrenceID(
            rawValue: "net-edge"
          ),
          permanentID: record.occurrenceID
        ),
      ]
    )

    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [mutation],
        identityAssignments: [segmentID: assignments]
      ) == nil
    )
    let partial = DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges(
      segmentID: segmentID,
      changes: Array(mutation.changes.prefix(1))
    )
    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [partial],
        identityAssignments: [segmentID: assignments]
      ) != nil
    )
    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [mutation],
        identityAssignments: [:]
      ) != nil
    )
  }

  @Test("Existing occurrence target move validates complete before and after pairs")
  func targetMoveRequiresCompletePairsWithoutNewIdentity() throws {
    let segmentID = try DesignMutationPlanSegmentID(rawValue: "relation-move")
    let before = try relation(
      occurrence: 7,
      target: 8,
      order: 1
    )
    let after = try relation(
      occurrence: 7,
      target: 9,
      order: 2
    )
    let beforeChanges = try before.projectionEntries().map {
      try DesignProjectionChange(
        family: .connectivity,
        before: $0,
        after: nil
      )
    }
    let afterChanges = try after.projectionEntries().map {
      try DesignProjectionChange(
        family: .connectivity,
        before: nil,
        after: $0
      )
    }
    let mutation = DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges(
      segmentID: segmentID,
      changes: beforeChanges + afterChanges
    )

    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [mutation],
        identityAssignments: [:]
      ) == nil
    )
    let partial = DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges(
      segmentID: segmentID,
      changes: beforeChanges + Array(afterChanges.prefix(1))
    )
    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [partial],
        identityAssignments: [:]
      ) != nil
    )
  }

  @Test("Existing occurrence deletion requires the complete before pair")
  func deletionRequiresCompleteBeforePair() throws {
    let segmentID = try DesignMutationPlanSegmentID(rawValue: "relation-delete")
    let record = try relation(
      occurrence: 11,
      target: 12,
      order: 1
    )
    let changes = try record.projectionEntries().map {
      try DesignProjectionChange(
        family: .connectivity,
        before: $0,
        after: nil
      )
    }

    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [
          .init(segmentID: segmentID, changes: changes),
        ],
        identityAssignments: [:]
      ) == nil
    )
    #expect(
      DesignProjectionRelationChangeValidator.validate(
        mutations: [
          .init(segmentID: segmentID, changes: Array(changes.prefix(1))),
        ],
        identityAssignments: [:]
      ) != nil
    )
  }

  private func relation(
    occurrence: UInt64,
    target: UInt64,
    order: UInt8
  ) throws -> DesignRelationOccurrenceRecord {
    try DesignRelationOccurrenceRecord(
      projectionFamily: .connectivity,
      occurrenceID: DesignRelationOccurrenceID(rawValue: occurrence),
      ownerEntityID: DesignEntityID(rawValue: 100),
      relationKindID: DesignRelationKindID(rawValue: "connects"),
      target: .local(DesignEntityID(rawValue: target)),
      orderKey: DesignCanonicalKey(bytes: [order]),
      attributesDigest: nil
    )
  }
}
