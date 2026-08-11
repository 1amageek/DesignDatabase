import Database

@Persistable
package struct DesignStagingRootModel {
  #Directory<DesignStagingRootModel>(
    "design-database",
    "staging-root"
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
  package var stagingDigestAlgorithm: String = ""
  package var stagingDigestValue: String = ""
  package var physicalIdentityDirectoryDigestAlgorithm: String = ""
  package var physicalIdentityDirectoryDigestValue: String = ""
  package var reachabilityGeneration: Int64 = 0
  package var state: Int64 = 0
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
}
