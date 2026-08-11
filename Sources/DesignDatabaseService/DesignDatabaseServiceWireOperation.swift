public enum DesignDatabaseServiceWireOperation: String, Sendable, Hashable, Codable {
  case negotiate
  case openSession = "open-session"
  case closeSession = "close-session"
  case shutdown
  case resolve
  case openSnapshot = "open-snapshot"
  case closeSnapshot = "close-snapshot"
  case query
  case diff
  case assessDisjointMerge = "assess-disjoint-merge"
  case publishDisjointMerge = "publish-disjoint-merge"
  case disjointMergePublicationStatus = "disjoint-merge-publication-status"
  case submit
  case commitStatus = "commit-status"
  case compareAndSetReference = "compare-and-set-reference"
  case referenceStatus = "reference-status"
  case retain
  case releaseRetention = "release-retention"
  case retentionStatus = "retention-status"
}
