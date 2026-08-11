import Database

@Persistable
package struct DesignDisjointMergeOperationModel {
  #Directory<DesignDisjointMergeOperationModel>(
    "design-database",
    "disjoint-merge-operation"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var outcomeKind: Int64 = 0
  package var payload: ByteString = ByteString()
  package var payloadDigestAlgorithm: String = ""
  package var payloadDigestValue: String = ""
}
