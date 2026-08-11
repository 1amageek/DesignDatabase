import Database

@Persistable
package struct DesignCollectionIntentModel {
  #Directory<DesignCollectionIntentModel>(
    "design-database",
    "collection-intent"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var candidateRevisionCount: Int64 = 0
  package var candidateRevisionIDs: String = ""
  package var originalRootSetDigestAlgorithm: String = ""
  package var originalRootSetDigestValue: String = ""
  package var physicalRootSetDigestAlgorithm: String = ""
  package var physicalRootSetDigestValue: String = ""
  package var physicalIdentityDirectoryDigestAlgorithm: String = ""
  package var physicalIdentityDirectoryDigestValue: String = ""
  package var physicalIdentityCount: UInt64 = 0
  package var deletedPhysicalIdentityCount: UInt64 = 0
  package var observedReachabilityGeneration: Int64 = 0
  package var admittedReachabilityGeneration: Int64 = 0
  package var completedReachabilityGeneration: Int64 = 0
  package var leaseObservationGeneration: UInt64 = 0
  package var state: Int64 = 0
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
}
