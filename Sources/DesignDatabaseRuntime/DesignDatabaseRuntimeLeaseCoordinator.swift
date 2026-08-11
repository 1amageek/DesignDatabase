import CircuiteFoundation
import DesignDatabaseCore

package actor DesignDatabaseRuntimeLeaseCoordinator {
  private enum State {
    case open
    case closed
  }

  private struct LeaseRecord: Sendable {
    let revision: DesignRevisionReference
    var materializationBindings: DesignProjectionMaterializationBindingSet?
  }

  private var state: State = .open
  private var nextIdentifier: UInt64 = 1
  private var observationGeneration: UInt64 = 0
  private var observationGenerationExhausted = false
  private var leases: [UInt64: LeaseRecord] = [:]
  private var deletionAdmissions: [
    String: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  ] = [:]

  package init() {}

  package func registerPending(
    revision: DesignRevisionReference
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeSnapshotLease {
    guard state == .open else { throw .attachmentClosed }
    if deletionAdmissions.values.contains(where: { $0.contains(revision) }) {
      throw .revisionDeleting(revision.revisionID.description)
    }
    let identifier = nextIdentifier
    let (next, identifierOverflow) = identifier.addingReportingOverflow(1)
    guard !identifierOverflow else {
      throw .generationExhausted(kind: "snapshot lease")
    }
    let nextObservation = try advancedObservationGeneration()
    guard leases[identifier] == nil else {
      throw .persistedStateCorrupt(
        reason: "A snapshot lease identifier was reused."
      )
    }
    nextIdentifier = next
    observationGeneration = nextObservation
    leases[identifier] = LeaseRecord(
      revision: revision,
      materializationBindings: nil
    )
    return DesignDatabaseRuntimeSnapshotLease(
      identifier: identifier,
      revision: revision
    )
  }

  package func activate(
    _ lease: DesignDatabaseRuntimeSnapshotLease,
    materializationBindings: DesignProjectionMaterializationBindingSet
  ) throws(DesignDatabaseRuntimeError) {
    guard state == .open else { throw .attachmentClosed }
    guard var record = leases[lease.identifier],
          record.revision == lease.revision,
          record.materializationBindings == nil else {
      throw .persistedStateCorrupt(
        reason: "A pending snapshot lease is missing or already active."
      )
    }
    let nextObservation = try advancedObservationGeneration()
    record.materializationBindings = materializationBindings
    leases[lease.identifier] = record
    observationGeneration = nextObservation
  }

  package func release(_ lease: DesignDatabaseRuntimeSnapshotLease) {
    guard leases[lease.identifier]?.revision == lease.revision else { return }
    leases.removeValue(forKey: lease.identifier)
    advanceObservationAfterMandatoryRelease()
  }

  package func admitDeletion(
    identifier: String,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeDeletionAdmissionToken {
    guard state == .open else { throw .attachmentClosed }
    guard !identifier.isEmpty else {
      throw .persistedStateCorrupt(
        reason: "A deletion admission identifier is empty."
      )
    }
    if let existing = deletionAdmissions[identifier] {
      guard existing == candidates else {
        throw .persistedStateCorrupt(
          reason: "A deletion admission identifier is bound to another candidate set."
        )
      }
      return DesignDatabaseRuntimeDeletionAdmissionToken(
        identifier: identifier,
        candidates: candidates
      )
    }
    if let overlappingAdmission = deletionAdmissions.values.first(
      where: { $0.overlaps(candidates) }
    ), let revision = overlappingAdmission.revisions.first(
      where: { candidates.contains($0) }
    ) {
      throw .revisionDeleting(revision.revisionID.description)
    }
    if let leasedRevision = leases.values.lazy.map(\.revision).first(
      where: { candidates.contains($0) }
    ) {
      throw .revisionDeleting(leasedRevision.revisionID.description)
    }
    let nextObservation = try advancedObservationGeneration()
    deletionAdmissions[identifier] = candidates
    observationGeneration = nextObservation
    return DesignDatabaseRuntimeDeletionAdmissionToken(
      identifier: identifier,
      candidates: candidates
    )
  }

  package func releaseDeletionAdmission(
    _ token: DesignDatabaseRuntimeDeletionAdmissionToken
  ) throws(DesignDatabaseRuntimeError) {
    guard let existing = deletionAdmissions[token.identifier] else { return }
    guard existing == token.candidates else {
      throw .persistedStateCorrupt(
        reason: "A deletion admission token does not match its candidate set."
      )
    }
    deletionAdmissions.removeValue(forKey: token.identifier)
    advanceObservationAfterMandatoryRelease()
  }

  package func observation()
    throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeLeaseObservation
  {
    guard !observationGenerationExhausted else {
      throw .generationExhausted(kind: "snapshot lease observation")
    }
    var pendingCount: UInt64 = 0
    var activeCount: UInt64 = 0
    for record in leases.values {
      if record.materializationBindings == nil {
        let (next, overflow) = pendingCount.addingReportingOverflow(1)
        guard !overflow else {
          throw .generationExhausted(kind: "pending snapshot lease count")
        }
        pendingCount = next
      } else {
        let (next, overflow) = activeCount.addingReportingOverflow(1)
        guard !overflow else {
          throw .generationExhausted(kind: "active snapshot lease count")
        }
        activeCount = next
      }
    }
    guard let admissionCount = UInt64(exactly: deletionAdmissions.count) else {
      throw .generationExhausted(kind: "deletion admission count")
    }
    return DesignDatabaseRuntimeLeaseObservation(
      generation: observationGeneration,
      pendingLeaseCount: pendingCount,
      activeLeaseCount: activeCount,
      deletionAdmissionCount: admissionCount
    )
  }

  package func close() {
    guard state == .open else { return }
    leases.removeAll(keepingCapacity: false)
    deletionAdmissions.removeAll(keepingCapacity: false)
    state = .closed
    advanceObservationAfterMandatoryRelease()
  }

  private func advancedObservationGeneration()
    throws(DesignDatabaseRuntimeError) -> UInt64
  {
    guard !observationGenerationExhausted else {
      throw .generationExhausted(kind: "snapshot lease observation")
    }
    let (next, overflow) = observationGeneration.addingReportingOverflow(1)
    guard !overflow else {
      throw .generationExhausted(kind: "snapshot lease observation")
    }
    return next
  }

  private func advanceObservationAfterMandatoryRelease() {
    let (next, overflow) = observationGeneration.addingReportingOverflow(1)
    if overflow {
      observationGenerationExhausted = true
    } else {
      observationGeneration = next
    }
  }
}
