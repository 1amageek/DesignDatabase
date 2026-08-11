import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeCollectionIntent {
  package enum State: Int64, Sendable {
    case admitted = 0
    case sweeping = 1
    case collected = 2
  }

  package static func makeAdmitted(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet,
    originalRootSetDigest: ContentDigest,
    physicalRootSetDigest: ContentDigest,
    physicalIdentityDirectoryDigest: ContentDigest,
    physicalIdentityCount: UInt64,
    observedReachabilityGeneration: Int64,
    admittedReachabilityGeneration: Int64,
    leaseObservationGeneration: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCollectionIntentModel {
    guard operation.databaseID == candidates.databaseID,
          observedReachabilityGeneration >= 0,
          admittedReachabilityGeneration > observedReachabilityGeneration,
          let candidateCount = Int64(exactly: candidates.revisions.count) else {
      throw .persistedStateCorrupt(
        reason: "A collection admission has an invalid database or generation binding."
      )
    }
    var model = DesignCollectionIntentModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    model.candidateRevisionCount = candidateCount
    model.candidateRevisionIDs = candidates.revisions
      .map(\.revisionID.description)
      .joined(separator: "\n")
    model.originalRootSetDigestAlgorithm = originalRootSetDigest.algorithm.rawValue
    model.originalRootSetDigestValue = originalRootSetDigest.hexadecimalValue
    model.physicalRootSetDigestAlgorithm = physicalRootSetDigest.algorithm.rawValue
    model.physicalRootSetDigestValue = physicalRootSetDigest.hexadecimalValue
    model.physicalIdentityDirectoryDigestAlgorithm =
      physicalIdentityDirectoryDigest.algorithm.rawValue
    model.physicalIdentityDirectoryDigestValue =
      physicalIdentityDirectoryDigest.hexadecimalValue
    model.physicalIdentityCount = physicalIdentityCount
    model.observedReachabilityGeneration = observedReachabilityGeneration
    model.admittedReachabilityGeneration = admittedReachabilityGeneration
    model.leaseObservationGeneration = leaseObservationGeneration
    model.state = State.admitted.rawValue
    return try updatingStateDigest(model, using: digester)
  }

  package static func recover(
    _ model: DesignCollectionIntentModel,
    maximumRevisionCount: UInt64 = 256,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> (
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet,
    originalRootSetDigest: ContentDigest,
    physicalRootSetDigest: ContentDigest,
    physicalIdentityDirectoryDigest: ContentDigest,
    physicalIdentityCount: UInt64,
    state: State
  ) {
    let operation: DesignDatabaseOperationReference
    let requestDigest: ContentDigest
    let rootSetDigest: ContentDigest
    let physicalRootSetDigest: ContentDigest
    let physicalIdentityDirectoryDigest: ContentDigest
    let revisionIDs: [DesignRevisionID]
    do {
      let databaseID = try DesignDatabaseID(hexadecimalValue: model.databaseID)
      operation = DesignDatabaseOperationReference(
        databaseID: databaseID,
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: model.subjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(rawValue: model.operationID)
      )
      requestDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: model.requestDigestAlgorithm),
        hexadecimalValue: model.requestDigestValue
      )
      rootSetDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.originalRootSetDigestAlgorithm
        ),
        hexadecimalValue: model.originalRootSetDigestValue
      )
      physicalRootSetDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.physicalRootSetDigestAlgorithm
        ),
        hexadecimalValue: model.physicalRootSetDigestValue
      )
      physicalIdentityDirectoryDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.physicalIdentityDirectoryDigestAlgorithm
        ),
        hexadecimalValue: model.physicalIdentityDirectoryDigestValue
      )
      let encodedIDs = model.candidateRevisionIDs.isEmpty
        ? []
        : model.candidateRevisionIDs.split(
            separator: "\n",
            omittingEmptySubsequences: false
          ).map(String.init)
      revisionIDs = try encodedIDs.map(DesignRevisionID.init(hexadecimalValue:))
    } catch {
      throw .persistedStateCorrupt(
        reason: "A collection intent contains a malformed identity or digest."
      )
    }
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          let persistedCount = UInt64(exactly: model.candidateRevisionCount),
          persistedCount == UInt64(revisionIDs.count),
          persistedCount > 0,
          model.deletedPhysicalIdentityCount <= model.physicalIdentityCount,
          model.observedReachabilityGeneration >= 0,
          model.admittedReachabilityGeneration
            > model.observedReachabilityGeneration,
          (model.state == State.collected.rawValue
            ? model.completedReachabilityGeneration
                > model.admittedReachabilityGeneration
            : model.completedReachabilityGeneration == 0),
          let state = State(rawValue: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A collection intent has a malformed scope, count, generation, or state."
      )
    }
    guard persistedCount <= maximumRevisionCount else {
      throw .deletionCandidateBudgetExceeded(
        limit: maximumRevisionCount,
        requested: persistedCount
      )
    }
    switch state {
    case .admitted:
      guard model.deletedPhysicalIdentityCount == 0,
            model.completedReachabilityGeneration == 0 else {
        throw .persistedStateCorrupt(
          reason: "An admitted collection intent has nonzero progress."
        )
      }
    case .sweeping:
      guard model.deletedPhysicalIdentityCount > 0,
            model.deletedPhysicalIdentityCount < model.physicalIdentityCount,
            model.completedReachabilityGeneration == 0 else {
        throw .persistedStateCorrupt(
          reason: "A sweeping collection intent has invalid nonterminal progress."
        )
      }
    case .collected:
      guard model.deletedPhysicalIdentityCount == model.physicalIdentityCount,
            model.completedReachabilityGeneration
              > model.admittedReachabilityGeneration else {
        throw .persistedStateCorrupt(
          reason: "A collected intent has incomplete terminal progress."
        )
      }
    }
    let candidates = try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
      revisions: revisionIDs.map {
        DesignRevisionReference(databaseID: operation.databaseID, revisionID: $0)
      },
      maximumRevisionCount: maximumRevisionCount
    )
    guard candidates.revisions.map(\.revisionID.description)
      .joined(separator: "\n") == model.candidateRevisionIDs else {
      throw .persistedStateCorrupt(
        reason: "A collection intent candidate set is not canonical."
      )
    }
    let expectedDigest = try stateDigest(model, using: digester)
    guard model.stateDigestAlgorithm == expectedDigest.algorithm.rawValue,
          model.stateDigestValue == expectedDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A collection intent state digest is invalid."
      )
    }
    return (
      operation,
      requestDigest,
      candidates,
      rootSetDigest,
      physicalRootSetDigest,
      physicalIdentityDirectoryDigest,
      model.physicalIdentityCount,
      state
    )
  }

  package static func advanced(
    _ model: DesignCollectionIntentModel,
    deletedPhysicalIdentityCount: UInt64,
    state: State,
    completedReachabilityGeneration: Int64? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCollectionIntentModel {
    guard let currentState = State(rawValue: model.state),
          currentState != .collected,
          deletedPhysicalIdentityCount >= model.deletedPhysicalIdentityCount,
          deletedPhysicalIdentityCount <= model.physicalIdentityCount else {
      throw .persistedStateCorrupt(
        reason: "A collection intent progress transition is invalid."
      )
    }
    switch (currentState, state) {
    case (.admitted, .sweeping), (.sweeping, .sweeping):
      guard deletedPhysicalIdentityCount > model.deletedPhysicalIdentityCount,
            deletedPhysicalIdentityCount < model.physicalIdentityCount,
            completedReachabilityGeneration == nil else {
        throw .persistedStateCorrupt(
          reason: "A nonterminal collection progress has a completion generation."
        )
      }
    case (.admitted, .collected), (.sweeping, .collected):
      guard deletedPhysicalIdentityCount == model.physicalIdentityCount,
            let completedReachabilityGeneration,
            completedReachabilityGeneration
              > model.admittedReachabilityGeneration else {
        throw .persistedStateCorrupt(
          reason: "A terminal collection progress is incomplete."
        )
      }
    default:
      throw .persistedStateCorrupt(
        reason: "A collection intent state transition is invalid."
      )
    }
    var updated = model
    updated.deletedPhysicalIdentityCount = deletedPhysicalIdentityCount
    updated.state = state.rawValue
    updated.completedReachabilityGeneration =
      completedReachabilityGeneration ?? 0
    return try updatingStateDigest(updated, using: digester)
  }

  private static func updatingStateDigest(
    _ model: DesignCollectionIntentModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCollectionIntentModel {
    var updated = model
    let digest = try stateDigest(updated, using: digester)
    updated.stateDigestAlgorithm = digest.algorithm.rawValue
    updated.stateDigestValue = digest.hexadecimalValue
    return updated
  }

  private static func stateDigest(
    _ model: DesignCollectionIntentModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard let candidateCount = UInt64(exactly: model.candidateRevisionCount),
          let observedGeneration = UInt64(
            exactly: model.observedReachabilityGeneration
          ),
          let admittedGeneration = UInt64(
            exactly: model.admittedReachabilityGeneration
          ),
          let state = UInt64(exactly: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A collection intent has a negative count, generation, or state."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CollectionIntent"
    )
    encoder.append(model.id)
    encoder.append(model.databaseID)
    encoder.append(model.subjectScopeID)
    encoder.append(model.operationID)
    encoder.append(model.requestDigestAlgorithm)
    encoder.append(model.requestDigestValue)
    encoder.append(candidateCount)
    encoder.append(model.candidateRevisionIDs)
    encoder.append(model.originalRootSetDigestAlgorithm)
    encoder.append(model.originalRootSetDigestValue)
    encoder.append(model.physicalRootSetDigestAlgorithm)
    encoder.append(model.physicalRootSetDigestValue)
    encoder.append(model.physicalIdentityDirectoryDigestAlgorithm)
    encoder.append(model.physicalIdentityDirectoryDigestValue)
    encoder.append(model.physicalIdentityCount)
    encoder.append(model.deletedPhysicalIdentityCount)
    encoder.append(observedGeneration)
    encoder.append(admittedGeneration)
    guard let completedGeneration = UInt64(
      exactly: model.completedReachabilityGeneration
    ) else {
      throw .persistedStateCorrupt(
        reason: "A collection intent has a negative completion generation."
      )
    }
    encoder.append(completedGeneration)
    encoder.append(model.leaseObservationGeneration)
    encoder.append(state)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "The collection intent digest could not be computed: \(error)"
      )
    }
  }
}
