import Database

@Persistable
package struct DesignDatabaseCatalogModel {
  #Directory<DesignDatabaseCatalogModel>("design-database", "catalog")

  package var id: String = "catalog"
  package var formatVersion: Int64 = 1
  package var databaseID: String = ""
  package var genesisRevisionID: String = ""
  package var schemaFingerprintAlgorithm: String = ""
  package var schemaFingerprintValue: String = ""
  package var designSchemaBundleDigestAlgorithm: String = ""
  package var designSchemaBundleDigestValue: String = ""
  package var registrationDigestAlgorithm: String = ""
  package var registrationDigestValue: String = ""
  package var creationRequestDigestAlgorithm: String = ""
  package var creationRequestDigestValue: String = ""
  package var capabilityCount: Int64 = 0
  package var capabilityIDs: String = ""
}
