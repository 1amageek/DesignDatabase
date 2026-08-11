import Database

@Persistable
package struct DesignIdentityReservationModel {
  #Directory<DesignIdentityReservationModel>(
    "design-database",
    "identity-reservation"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var subjectScopeID: String = ""
  package var operationID: String = ""
  package var requestDigestAlgorithm: String = ""
  package var requestDigestValue: String = ""
  package var planDigestAlgorithm: String = ""
  package var planDigestValue: String = ""
  package var firstEntityValue: UInt64 = 0
  package var entityCount: UInt64 = 0
  package var firstRelationOccurrenceValue: UInt64 = 0
  package var relationOccurrenceCount: UInt64 = 0
  package var assignmentDigestAlgorithm: String = ""
  package var assignmentDigestValue: String = ""
  package var validatedDirectoryDigestAlgorithm: String = ""
  package var validatedDirectoryDigestValue: String = ""
  package var validatedMutationCount: UInt64 = 0
  package var allocatorGeneration: UInt64 = 0
}
