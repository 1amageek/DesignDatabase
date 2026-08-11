import Database

@Persistable
package struct DesignOperationClaimModel {
  #Directory<DesignOperationClaimModel>("design-database", "operation-claim")

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var operationKind: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
}
