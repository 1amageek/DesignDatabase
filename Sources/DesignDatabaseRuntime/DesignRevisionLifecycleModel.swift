import Database

@Persistable
package struct DesignRevisionLifecycleModel {
  #Directory<DesignRevisionLifecycleModel>(
    "design-database",
    "revision-lifecycle"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var revisionID: String = ""
  package var state: Int64 = 0
  package var reachabilityGeneration: Int64 = 0
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
}
