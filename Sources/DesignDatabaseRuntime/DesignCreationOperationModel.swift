import Database

@Persistable
package struct DesignCreationOperationModel {
  #Directory<DesignCreationOperationModel>("design-database", "creation-operation")

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var genesisRevisionID: String = ""
  package var outcomeDigestAlgorithm: String = ""
  package var outcomeDigestValue: String = ""
}
