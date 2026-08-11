import Database

@Persistable
package struct DesignCommitBuildIntentModel {
  #Directory<DesignCommitBuildIntentModel>(
    "design-database",
    "commit-build-intent"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var planDigestAlgorithm: String = ""
  package var planDigestValue: String = ""
  package var baseRevisionID: String = ""
  package var candidateRevisionID: String = ""
  package var preparedDirectoryDigestAlgorithm: String = ""
  package var preparedDirectoryDigestValue: String = ""
  package var preparedMutationCount: UInt64 = 0
  package var stagingDigestAlgorithm: String = ""
  package var stagingDigestValue: String = ""
  package var expectedDomainWriteCount: UInt64 = 0
  package var stagedDomainWriteCount: UInt64 = 0
  package var expectedProjectionNodeCount: UInt64 = 0
  package var stagedProjectionNodeCount: UInt64 = 0
  package var progressDigestAlgorithm: String = ""
  package var progressDigestValue: String = ""
  package var state: Int64 = 0
}
