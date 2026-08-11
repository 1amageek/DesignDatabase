import Database

@Persistable
package struct DesignCommitAbandonmentOperationModel {
  #Directory<DesignCommitAbandonmentOperationModel>(
    "design-database",
    "commit-abandonment-operation"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var outcomeKind: Int64 = 0
  package var targetSubjectScopeID: String = ""
  package var targetOperationID: String = ""
  package var targetRequestDigestAlgorithm: String = ""
  package var targetRequestDigestValue: String = ""
  package var abandonmentReason: String = ""
  package var evidenceDigestAlgorithm: String = ""
  package var evidenceDigestValue: String = ""
  package var targetCommitOutcomeDigestAlgorithm: String = ""
  package var targetCommitOutcomeDigestValue: String = ""
  package var stagingRootTerminalized: Bool = false
  package var reachabilityGeneration: Int64 = 0
  package var rejectionKind: Int64 = 0
  package var rejectionDigestAlgorithm: String = ""
  package var rejectionDigestValue: String = ""
  package var outcomeDigestAlgorithm: String = ""
  package var outcomeDigestValue: String = ""
}
