import Database

@Persistable
package struct DesignReferenceOperationModel {
  #Directory<DesignReferenceOperationModel>("design-database", "reference-operation")

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var referenceName: String = ""
  package var outcomeKind: Int64 = 0
  package var previousRevisionID: String = ""
  package var currentRevisionID: String = ""
  package var generation: Int64 = 0
  package var rejectionKind: Int64 = 0
  package var rejectionRevisionID: String = ""
  package var outcomeDigestAlgorithm: String = ""
  package var outcomeDigestValue: String = ""
}
