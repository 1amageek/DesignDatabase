import Database

@Persistable
package struct DesignCollectionPhysicalIdentityDirectoryModel {
  #Directory<DesignCollectionPhysicalIdentityDirectoryModel>(
    "design-database",
    "collection-physical-identity-directory"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var identityCount: UInt64 = 0
  package var payload: ByteString = ByteString()
  package var payloadDigestAlgorithm: String = ""
  package var payloadDigestValue: String = ""
  package var identitySetDigestAlgorithm: String = ""
  package var identitySetDigestValue: String = ""
}
