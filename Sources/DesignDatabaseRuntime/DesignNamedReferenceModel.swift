import Database

@Persistable
package struct DesignNamedReferenceModel {
  #Directory<DesignNamedReferenceModel>("design-database", "named-reference")

  package var id: String = ""
  package var databaseID: String = ""
  package var revisionID: String = ""
  package var generation: Int64 = 0
}
