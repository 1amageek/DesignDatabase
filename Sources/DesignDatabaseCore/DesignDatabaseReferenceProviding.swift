public protocol DesignDatabaseReferenceProviding: Sendable {
  func create(
    _ request: DesignReferenceDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseReference
}
