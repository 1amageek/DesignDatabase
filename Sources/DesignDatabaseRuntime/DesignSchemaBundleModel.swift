import Database

@Persistable
package struct DesignSchemaBundleModel {
  #Directory<DesignSchemaBundleModel>("design-database", "schema-bundle")

  package var id: String = ""
  package var rootDigestAlgorithm: String = ""
  package var rootDigestValue: String = ""
  package var memberCount: Int64 = 0
  package var memberIDs: String = ""
}
