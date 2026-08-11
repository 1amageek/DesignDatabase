import Database

@Persistable
package struct DesignDatabaseCapabilityModel {
  #Directory<DesignDatabaseCapabilityModel>("design-database", "capability")

  package var id: String = ""
  package var databaseID: String = ""
  package var capabilityID: String = ""
  package var lowerMajor: Int64 = 0
  package var lowerMinor: Int64 = 0
  package var lowerPatch: Int64 = 0
  package var upperMajor: Int64 = 0
  package var upperMinor: Int64 = 0
  package var upperPatch: Int64 = 0
}
