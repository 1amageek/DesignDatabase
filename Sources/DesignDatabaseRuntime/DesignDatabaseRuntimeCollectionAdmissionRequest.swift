import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeCollectionAdmissionRequest: Sendable {
  package let operation: DesignDatabaseOperationReference
  package let candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  package let requestDigest: ContentDigest

  package init(
    operation: DesignDatabaseOperationReference,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    guard operation.databaseID == candidates.databaseID else {
      throw .persistedStateCorrupt(
        reason: "A collection admission request crosses a database boundary."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CollectionAdmissionRequest"
    )
    encoder.append(operation.databaseID.description)
    encoder.append(operation.authorizationSubjectScopeID.description)
    encoder.append(operation.operationID.rawValue)
    guard let candidateCount = UInt64(exactly: candidates.revisions.count) else {
      throw .deletionCandidateBudgetExceeded(
        limit: UInt64.max,
        requested: UInt64.max
      )
    }
    encoder.append(candidateCount)
    for revision in candidates.revisions {
      encoder.append(revision.revisionID.description)
    }
    self.operation = operation
    self.candidates = candidates
    self.requestDigest = try encoder.finalize(using: digester)
  }
}
