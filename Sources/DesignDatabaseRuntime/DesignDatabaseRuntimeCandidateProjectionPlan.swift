import DesignDatabaseCore

package struct DesignDatabaseRuntimeCandidateProjectionPlan: Sendable {
  package struct MutationChanges: Sendable {
    package let segmentID: DesignMutationPlanSegmentID
    package let changes: [DesignProjectionChange]

    package init(
      segmentID: DesignMutationPlanSegmentID,
      changes: [DesignProjectionChange]
    ) {
      self.segmentID = segmentID
      self.changes = changes
    }
  }

  package let materializations: [DesignProjectionTreeMaterialization]
  package let mutations: [MutationChanges]
}
