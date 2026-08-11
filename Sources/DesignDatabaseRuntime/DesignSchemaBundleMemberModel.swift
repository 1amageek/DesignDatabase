import Database

@Persistable
package struct DesignSchemaBundleMemberModel {
  #Directory<DesignSchemaBundleMemberModel>("design-database", "schema-bundle-member")

  package var id: String = ""
  package var bundleID: String = ""
  package var schemaID: String = ""
  package var versionMajor: Int64 = 0
  package var versionMinor: Int64 = 0
  package var versionPatch: Int64 = 0
  package var canonicalDigestAlgorithm: String = ""
  package var canonicalDigestValue: String = ""
}
