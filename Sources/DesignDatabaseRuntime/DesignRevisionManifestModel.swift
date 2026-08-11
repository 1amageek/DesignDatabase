import Database

@Persistable
package struct DesignRevisionManifestModel {
  #Directory<DesignRevisionManifestModel>("design-database", "revision-manifest")

  package var id: String = ""
  package var databaseID: String = ""
  package var parentCount: Int64 = 0
  package var parentRevisionIDs: String = ""
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
  package var schemaRootDigestAlgorithm: String = ""
  package var schemaRootDigestValue: String = ""
  package var dependencyRootDigestAlgorithm: String = ""
  package var dependencyRootDigestValue: String = ""
  package var dependencyLockEntryCount: Int64 = 0
  package var dependencyLockEntries: String = ""
  package var dependencyGraphDigestAlgorithm: String = ""
  package var dependencyGraphDigestValue: String = ""
  package var facetRootCount: Int64 = 0
  package var facetRoots: String = ""
  package var projectionDescriptorCount: Int64 = 0
  package var projectionDescriptorDigests: String = ""
  package var directChangeRootDigestAlgorithm: String = ""
  package var directChangeRootDigestValue: String = ""
}
