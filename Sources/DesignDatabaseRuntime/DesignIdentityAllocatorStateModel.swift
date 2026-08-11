import Database

@Persistable
package struct DesignIdentityAllocatorStateModel {
  #Directory<DesignIdentityAllocatorStateModel>(
    "design-database",
    "identity-allocator"
  )

  package var id: String = ""
  package var databaseID: String = ""
  package var nextEntityValue: UInt64 = 0
  package var nextRelationOccurrenceValue: UInt64 = 0
  package var generation: UInt64 = 0
}
