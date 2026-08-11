import CircuiteFoundation

public protocol DesignDisjointMergePublishing: Sendable {
  func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationResult

  func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationStatus
}
