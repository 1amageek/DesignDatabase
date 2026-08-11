package struct DesignDatabaseRuntimeLeaseObservation: Sendable, Equatable {
  package let generation: UInt64
  package let pendingLeaseCount: UInt64
  package let activeLeaseCount: UInt64
  package let deletionAdmissionCount: UInt64
}
