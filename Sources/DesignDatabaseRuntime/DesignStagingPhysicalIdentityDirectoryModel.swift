import Database

@Persistable
package struct DesignStagingPhysicalIdentityDirectoryModel {
  #Directory<DesignStagingPhysicalIdentityDirectoryModel>(
    "design-database",
    "staging-physical-identity-directory"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var planDigestAlgorithm: String = ""
  package var planDigestValue: String = ""
  package var candidateRevisionID: String = ""
  package var identityCount: UInt64 = 0
  package var payload: ByteString = ByteString()
  package var payloadDigestAlgorithm: String = ""
  package var payloadDigestValue: String = ""
}
