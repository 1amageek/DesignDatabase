import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeReservedIdentities: Sendable {
  package let assignments: [
    DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
  ]
  package let assignmentDigest: ContentDigest
}
