import Database

@Persistable
package struct DesignRevisionPhysicalIdentityDirectoryModel {
  #Directory<DesignRevisionPhysicalIdentityDirectoryModel>(
    "design-database",
    "revision-physical-identity-directory"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var revisionID: String = ""
  package var identityCount: UInt64 = 0
  package var payload: ByteString = ByteString()
  package var payloadDigestAlgorithm: String = ""
  package var payloadDigestValue: String = ""
}
