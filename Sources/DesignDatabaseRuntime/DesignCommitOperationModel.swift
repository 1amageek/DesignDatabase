import Database

@Persistable
package struct DesignCommitOperationModel {
  #Directory<DesignCommitOperationModel>("design-database", "commit-operation")

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var planDigestAlgorithm: String = ""
  package var planDigestValue: String = ""
  package var outcomeKind: Int64 = 0
  package var baseRevisionID: String = ""
  package var candidateRevisionID: String = ""
  package var stateDigestAlgorithm: String = ""
  package var stateDigestValue: String = ""
  package var changeSetDigestAlgorithm: String = ""
  package var changeSetDigestValue: String = ""
  package var schemaBundleDigestAlgorithm: String = ""
  package var schemaBundleDigestValue: String = ""
  package var dependencyRootDigestAlgorithm: String = ""
  package var dependencyRootDigestValue: String = ""
  package var dependencyGraphDigestAlgorithm: String = ""
  package var dependencyGraphDigestValue: String = ""
  package var facetRootCount: Int64 = 0
  package var facetRoots: String = ""
  package var rejectionKind: Int64 = 0
  package var rejectionExpectedDigestAlgorithm: String = ""
  package var rejectionExpectedDigestValue: String = ""
  package var rejectionActualDigestAlgorithm: String = ""
  package var rejectionActualDigestValue: String = ""
  package var rejectionSchemaID: String = ""
  package var rejectionAdapterVersion: String = ""
  package var rejectionSegmentID: String = ""
  package var rejectionDetail: String = ""
  package var rejectionLimit: String = ""
  package var rejectionRequested: String = ""
  package var rejectionRevisionID: String = ""
  package var rejectionDiagnosticsJSON: String = ""
  package var rejectionDiagnosticsDigestAlgorithm: String = ""
  package var rejectionDiagnosticsDigestValue: String = ""
  package var rejectionMaintenanceSubjectScopeID: String = ""
  package var rejectionMaintenanceOperationID: String = ""
  package var rejectionMaintenanceRequestDigestAlgorithm: String = ""
  package var rejectionMaintenanceRequestDigestValue: String = ""
  package var rejectionMaintenanceReason: String = ""
  package var rejectionMaintenanceEvidenceDigestAlgorithm: String = ""
  package var rejectionMaintenanceEvidenceDigestValue: String = ""
  package var outcomeDigestAlgorithm: String = ""
  package var outcomeDigestValue: String = ""
}
