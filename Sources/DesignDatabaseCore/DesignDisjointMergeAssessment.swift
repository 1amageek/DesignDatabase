public enum DesignDisjointMergeAssessment: Sendable, Hashable, DesignDatabaseSerializable {
  case requiresSemanticValidation(DesignDisjointMergeCandidate)
  case conflict(DesignDisjointMergeConflict)
}
