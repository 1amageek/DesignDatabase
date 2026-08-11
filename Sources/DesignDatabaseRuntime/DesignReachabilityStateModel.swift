import Database

@Persistable
package struct DesignReachabilityStateModel {
  #Directory<DesignReachabilityStateModel>("design-database", "reachability-state")

  package var id: String = "active"
  package var databaseID: String = ""
  package var generation: Int64 = 0
}
