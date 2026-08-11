import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeCandidateProjectionPlanner {
  package enum Outcome: Sendable {
    case planned(DesignDatabaseRuntimeCandidateProjectionPlan)
    case rejected(DesignCommitRejection.Reason)
  }

  private struct Contribution: Sendable {
    let segmentID: DesignMutationPlanSegmentID
    let change: DesignProjectionChange
  }

  package static func plan(
    facetProjection: DesignProjectionTreeMaterialization,
    base: DesignProjectionRuntimeState,
    prepared: [any DesignDatabaseRuntimePreparedMutation],
    identityAssignments: [
      DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
    ],
    reads: DesignDatabaseRuntimeReadSnapshot,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> Outcome {
    guard facetProjection.descriptor.family == .facet else {
      throw .persistedStateCorrupt(
        reason: "The Runtime-derived candidate projection is not the facet family."
      )
    }

    var mutationChanges: [
      DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges
    ] = []
    mutationChanges.reserveCapacity(prepared.count)
    var contributions: [Contribution] = []

    for mutation in prepared {
      let changes = mutation.projectionChanges.sorted()
      mutationChanges.append(
        .init(segmentID: mutation.segmentID, changes: changes)
      )
      for change in changes {
        guard change.family != .facet,
              change.family != .directChange else {
          return .rejected(
            invalidSegment(
              mutation.segmentID,
              "A domain adapter cannot contribute a Runtime-owned projection family."
            )
          )
        }
        contributions.append(
          Contribution(segmentID: mutation.segmentID, change: change)
        )
      }
    }

    contributions.sort {
      if $0.change != $1.change { return $0.change < $1.change }
      return $0.segmentID < $1.segmentID
    }
    for index in contributions.indices.dropFirst() where
      contributions[index - 1].change.family
        == contributions[index].change.family
        && contributions[index - 1].change.key
          == contributions[index].change.key {
      return .rejected(
        invalidSegment(
          contributions[index].segmentID,
          "Projection changes contain a duplicate family and canonical key."
        )
      )
    }

    var materializations = [facetProjection]
    materializations.reserveCapacity(
      base.materializations.count + contributions.count + 1
    )
    let grouped = Dictionary(grouping: contributions) { $0.change.family }

    for contribution in contributions where
      contribution.change.family == .entity
        && contribution.change.before == nil {
      guard let after = contribution.change.after else { continue }
      if let rejection = validateInsertedEntityIdentity(
        entry: after,
        segmentID: contribution.segmentID,
        assignments: identityAssignments[contribution.segmentID]
      ) {
        return .rejected(rejection)
      }
    }
    if let rejection = DesignProjectionRelationChangeValidator.validate(
      mutations: mutationChanges,
      identityAssignments: identityAssignments
    ) {
      return .rejected(rejection)
    }

    for (family, baseMaterialization) in base.materializations.sorted(
      by: { $0.key < $1.key }
    ) where family != .facet {
      if let changed = grouped[family], let first = changed.first {
        switch try await DesignProjectionTreeUpdater().update(
          base: baseMaterialization,
          changes: changed.map(\.change),
          reads: reads,
          digester: digester
        ) {
        case .updated(let materialization):
          materializations.append(materialization)
        case .rejected(let reason):
          return .rejected(invalidSegment(first.segmentID, reason))
        case .budgetExceeded(let limit, let requested):
          return .rejected(.budgetExceeded(limit: limit, requested: requested))
        }
      } else {
        materializations.append(baseMaterialization.inheritedTree())
      }
    }

    for family in grouped.keys.sorted() {
      guard base.materializations[family] == nil,
            let familyContributions = grouped[family] else {
        continue
      }
      var entries: [DesignProjectionEntry] = []
      entries.reserveCapacity(familyContributions.count)
      for contribution in familyContributions {
        guard contribution.change.before == nil,
              let after = contribution.change.after else {
          return .rejected(
            invalidSegment(
              contribution.segmentID,
              "The first materialization of a projection family must contain insertion-only changes."
            )
          )
        }
        entries.append(after)
      }
      materializations.append(
        try DesignProjectionTreeBuilder().build(
          family: family,
          entries: entries,
          digester: digester
        )
      )
    }

    return .planned(
      DesignDatabaseRuntimeCandidateProjectionPlan(
        materializations: materializations,
        mutations: mutationChanges
      )
    )
  }

  private static func validateInsertedEntityIdentity(
    entry: DesignProjectionEntry,
    segmentID: DesignMutationPlanSegmentID,
    assignments: DesignMutationIdentityAssignments?
  ) -> DesignCommitRejection.Reason? {
    let record: DesignEntityProjectionRecord
    do {
      record = try DesignEntityProjectionRecord(projectionEntry: entry)
    } catch {
      return invalidSegment(
        segmentID,
        "An entity projection change is not a canonical entity record."
      )
    }
    guard assignments?.entities.contains(where: {
      $0.permanentID == record.entityID
    }) == true else {
      return invalidSegment(
        segmentID,
        "An inserted entity projection does not use an identity reserved for its segment."
      )
    }
    return nil
  }

  private static func invalidSegment(
    _ segmentID: DesignMutationPlanSegmentID,
    _ reason: String
  ) -> DesignCommitRejection.Reason {
    .invalidSegmentPayload(segmentID: segmentID, reason: reason)
  }
}
