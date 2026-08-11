package enum DesignCommitBuildIntentState: Int64, Sendable {
  case staging = 0
  case prepared = 1
  case committed = 2
  case rejected = 3
}
