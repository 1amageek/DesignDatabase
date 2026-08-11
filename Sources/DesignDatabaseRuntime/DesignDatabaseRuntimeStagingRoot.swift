import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeStagingRootState: Int64, Sendable {
  case active = 0
  case published = 1
  case rejected = 2
  case reclaiming = 3
  case reclaimed = 4
}

package enum DesignDatabaseRuntimeStagingRoot {
  package static func makeActive(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    stagingDigest: ContentDigest,
    physicalIdentityDirectoryDigest: ContentDigest,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    guard reachabilityGeneration > 0 else {
      throw .persistedStateCorrupt(
        reason: "An active staging root requires a positive reachability generation."
      )
    }
    var model = DesignStagingRootModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
    model.requestDigestValue = submission.requestDigest.hexadecimalValue
    model.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
    model.planDigestValue = submission.plan.planDigest.hexadecimalValue
    model.candidateRevisionID = candidateRevision.revisionID.description
    model.stagingDigestAlgorithm = stagingDigest.algorithm.rawValue
    model.stagingDigestValue = stagingDigest.hexadecimalValue
    model.physicalIdentityDirectoryDigestAlgorithm =
      physicalIdentityDirectoryDigest.algorithm.rawValue
    model.physicalIdentityDirectoryDigestValue =
      physicalIdentityDirectoryDigest.hexadecimalValue
    model.reachabilityGeneration = reachabilityGeneration
    model.state = DesignDatabaseRuntimeStagingRootState.active.rawValue
    return try updatingStateDigest(model, using: digester)
  }

  package static func terminalized(
    _ model: DesignStagingRootModel,
    state: DesignDatabaseRuntimeStagingRootState,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    guard model.state == DesignDatabaseRuntimeStagingRootState.active.rawValue,
          reachabilityGeneration > model.reachabilityGeneration,
          state == .published || state == .rejected else {
      throw .persistedStateCorrupt(
        reason: "A staging root terminal transition has an invalid state."
      )
    }
    var updated = model
    updated.state = state.rawValue
    updated.reachabilityGeneration = reachabilityGeneration
    return try updatingStateDigest(updated, using: digester)
  }

  package static func advancedActive(
    _ model: DesignStagingRootModel,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    guard model.state == DesignDatabaseRuntimeStagingRootState.active.rawValue,
          reachabilityGeneration > model.reachabilityGeneration else {
      throw .persistedStateCorrupt(
        reason: "An active staging root progress transition has an invalid generation."
      )
    }
    var updated = model
    updated.reachabilityGeneration = reachabilityGeneration
    return try updatingStateDigest(updated, using: digester)
  }

  package static func beganReclamation(
    _ model: DesignStagingRootModel,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    try transitionedReclamation(
      model,
      from: .rejected,
      to: .reclaiming,
      reachabilityGeneration: reachabilityGeneration,
      using: digester
    )
  }

  package static func completedReclamation(
    _ model: DesignStagingRootModel,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    try transitionedReclamation(
      model,
      from: .reclaiming,
      to: .reclaimed,
      reachabilityGeneration: reachabilityGeneration,
      using: digester
    )
  }

  @discardableResult
  package static func validate(
    _ model: DesignStagingRootModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    stagingDigest: ContentDigest,
    expectedState: DesignDatabaseRuntimeStagingRootState? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeStagingRootState {
    try validateStatus(
      model,
      operation: operation,
      requestDigest: submission.requestDigest,
      planDigest: submission.plan.planDigest,
      candidateRevisionID: candidateRevision.revisionID.description,
      stagingDigest: stagingDigest,
      expectedState: expectedState,
      using: digester
    )
  }

  package static func validateStatus(
    _ model: DesignStagingRootModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    candidateRevisionID: String,
    stagingDigest: ContentDigest,
    expectedState: DesignDatabaseRuntimeStagingRootState? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeStagingRootState {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm
            == requestDigest.algorithm.rawValue,
          model.requestDigestValue
            == requestDigest.hexadecimalValue,
          model.planDigestAlgorithm
            == planDigest.algorithm.rawValue,
          model.planDigestValue
            == planDigest.hexadecimalValue,
          model.candidateRevisionID == candidateRevisionID,
          model.stagingDigestAlgorithm == stagingDigest.algorithm.rawValue,
          model.stagingDigestValue == stagingDigest.hexadecimalValue,
          model.reachabilityGeneration > 0,
          let state = DesignDatabaseRuntimeStagingRootState(
            rawValue: model.state
          ), expectedState == nil || state == expectedState else {
      throw .persistedStateCorrupt(
        reason: "A staging root does not match its exact commit build."
      )
    }
    _ = try physicalIdentityDirectoryDigest(model)
    let expectedDigest = try stateDigest(model, using: digester)
    guard model.stateDigestAlgorithm == expectedDigest.algorithm.rawValue,
          model.stateDigestValue == expectedDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A staging root state digest is invalid."
      )
    }
    return state
  }

  package static func physicalIdentityDirectoryDigest(
    _ model: DesignStagingRootModel
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      return try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.physicalIdentityDirectoryDigestAlgorithm
        ),
        hexadecimalValue: model.physicalIdentityDirectoryDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A staging root has an invalid physical identity directory digest."
      )
    }
  }

  private static func updatingStateDigest(
    _ model: DesignStagingRootModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    var updated = model
    let digest = try stateDigest(updated, using: digester)
    updated.stateDigestAlgorithm = digest.algorithm.rawValue
    updated.stateDigestValue = digest.hexadecimalValue
    return updated
  }

  private static func transitionedReclamation(
    _ model: DesignStagingRootModel,
    from source: DesignDatabaseRuntimeStagingRootState,
    to destination: DesignDatabaseRuntimeStagingRootState,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignStagingRootModel {
    guard model.state == source.rawValue,
          reachabilityGeneration > model.reachabilityGeneration else {
      throw .persistedStateCorrupt(
        reason: "A staging root reclamation transition has an invalid state."
      )
    }
    var updated = model
    updated.state = destination.rawValue
    updated.reachabilityGeneration = reachabilityGeneration
    return try updatingStateDigest(updated, using: digester)
  }

  private static func stateDigest(
    _ model: DesignStagingRootModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard let reachabilityGeneration = UInt64(
      exactly: model.reachabilityGeneration
    ), let state = UInt64(exactly: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A staging root has a negative generation or state."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.StagingRoot"
    )
    encoder.append(model.id)
    encoder.append(model.databaseID)
    encoder.append(model.subjectScopeID)
    encoder.append(model.operationID)
    encoder.append(model.requestDigestAlgorithm)
    encoder.append(model.requestDigestValue)
    encoder.append(model.planDigestAlgorithm)
    encoder.append(model.planDigestValue)
    encoder.append(model.candidateRevisionID)
    encoder.append(model.stagingDigestAlgorithm)
    encoder.append(model.stagingDigestValue)
    encoder.append(model.physicalIdentityDirectoryDigestAlgorithm)
    encoder.append(model.physicalIdentityDirectoryDigestValue)
    encoder.append(reachabilityGeneration)
    encoder.append(state)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "The staging root state digest could not be computed: \(error)"
      )
    }
  }
}
