import Database

@Persistable
package struct DesignRetentionOperationModel {
  #Directory<DesignRetentionOperationModel>("design-database", "retention-operation")

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var outcomeKind: Int64 = 0
  package var claimID: String = ""
  package var revisionID: String = ""
  package var generation: Int64 = 0
  package var reachabilityGeneration: Int64 = 0
  package var retentionState: Int64 = 0
  package var rejectionKind: Int64 = 0
  package var rejectionActualGeneration: Int64 = 0
  package var outcomeDigestAlgorithm: String = ""
  package var outcomeDigestValue: String = ""
}
