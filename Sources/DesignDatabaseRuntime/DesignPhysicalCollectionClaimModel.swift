import Database

@Persistable
package struct DesignPhysicalCollectionClaimModel {
  #Directory<DesignPhysicalCollectionClaimModel>(
    "design-database",
    "physical-collection-claim"
  )

  package var id: String = ""
  package var collectionIntentID: String = ""
  package var canonicalIdentity: ByteString = ByteString()
  package var identityDigestAlgorithm: String = ""
  package var identityDigestValue: String = ""
  package var state: Int64 = 0
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
}
