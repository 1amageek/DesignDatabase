import Database

@Persistable
package struct DesignRevisionRetentionModel {
  #Directory<DesignRevisionRetentionModel>("design-database", "revision-retention")

  package var id: String = ""
  package var databaseID: String = ""
  package var claimID: String = ""
  package var ownerSubjectScopeID: String = ""
  package var revisionID: String = ""
  package var reason: String = ""
  package var evidenceDigestAlgorithm: String = ""
  package var evidenceDigestValue: String = ""
  package var generation: Int64 = 0
  package var state: Int64 = 0
}
