import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeCommitBuildIntent {
  package static let stagingTransactionWriteLimit: UInt64 = 64

  package static func stagingDigest(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectory: DesignDatabaseRuntimePreparedMutationDirectory,
    prepared: [any DesignDatabaseRuntimePreparedMutation],
    projectionPlan: DesignDatabaseRuntimeCandidateProjectionPlan,
    projections: DesignDatabaseRuntimeProjectionStagingDirectory,
    physicalIdentityDirectory:
      DesignDatabaseRuntimeStagingPhysicalIdentityDirectory,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CommitBuildIntent"
    )
    encoder.append(operation.databaseID.description)
    encoder.append(operation.authorizationSubjectScopeID.description)
    encoder.append(operation.operationID.rawValue)
    encoder.append(submission.requestDigest)
    encoder.append(submission.plan.planDigest)
    encoder.append(submission.plan.baseRevision.revisionID.description)
    encoder.append(candidateRevision.revisionID.description)
    encoder.append(preparedDirectory.digest)
    encoder.append(physicalIdentityDirectory.digest)
    guard projectionPlan.mutations.count == prepared.count,
          let preparedCount = UInt32(exactly: prepared.count),
          let projectionCount = UInt32(exactly: projections.entries.count) else {
      throw .commitTransactionFailed(
        reason: "The prepared staging directory is not representable."
      )
    }
    encoder.append(preparedCount)
    for (index, mutation) in prepared.enumerated() {
      let changes = projectionPlan.mutations[index]
      guard changes.segmentID == mutation.segmentID else {
        throw .persistedStateCorrupt(
          reason: "The candidate projection plan changed prepared mutation order."
        )
      }
      encoder.append(mutation.segmentID.rawValue)
      encoder.append(mutation.writeCount)
      encoder.append(mutation.facetRootDigest)
      encoder.append(mutation.changeContributionDigest)
      try encoder.append(projectionChanges: changes.changes)
    }
    encoder.append(projectionCount)
    for entry in projections.entries {
      let projection = entry.materialization
      encoder.append(projection.descriptor.family.rawValue)
      encoder.append(projection.descriptorDigest)
      encoder.append(projection.reference.semanticDescriptorDigest)
      encoder.append(projection.reference.bindingGeneration)
      encoder.append(projection.reference.physicalCodecVersion.major)
      encoder.append(projection.reference.physicalCodecVersion.minor)
      encoder.append(projection.reference.physicalProfileDigest)
      encoder.append(projection.reference.rootNodeDigest)
      encoder.append(projection.rootLevel)
      encoder.append(projection.totalNodeCount)
      encoder.append(entry.endIndex - entry.startIndex)
    }
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "The commit staging digest could not be computed: \(error)"
      )
    }
  }

  package static func make(
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectoryDigest: ContentDigest,
    preparedMutationCount: UInt64,
    stagingDigest: ContentDigest,
    expectedDomainWriteCount: UInt64,
    expectedProjectionNodeCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentModel {
    var model = DesignCommitBuildIntentModel()
    model.id = DesignDatabaseRuntimeOperationClaim.key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.requestDigestAlgorithm = submission.requestDigest.algorithm.rawValue
    model.requestDigestValue = submission.requestDigest.hexadecimalValue
    model.planDigestAlgorithm = submission.plan.planDigest.algorithm.rawValue
    model.planDigestValue = submission.plan.planDigest.hexadecimalValue
    model.baseRevisionID = submission.plan.baseRevision.revisionID.description
    model.candidateRevisionID = candidateRevision.revisionID.description
    model.preparedDirectoryDigestAlgorithm = preparedDirectoryDigest.algorithm.rawValue
    model.preparedDirectoryDigestValue = preparedDirectoryDigest.hexadecimalValue
    model.preparedMutationCount = preparedMutationCount
    model.stagingDigestAlgorithm = stagingDigest.algorithm.rawValue
    model.stagingDigestValue = stagingDigest.hexadecimalValue
    model.expectedDomainWriteCount = expectedDomainWriteCount
    model.expectedProjectionNodeCount = expectedProjectionNodeCount
    model.state = DesignCommitBuildIntentState.staging.rawValue
    return try updatingProgressDigest(model, using: digester)
  }

  package static func validate(
    _ model: DesignCommitBuildIntentModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    preparedDirectoryDigest: ContentDigest,
    preparedMutationCount: UInt64,
    stagingDigest: ContentDigest,
    expectedDomainWriteCount: UInt64,
    expectedProjectionNodeCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentState {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm
            == submission.requestDigest.algorithm.rawValue,
          model.requestDigestValue
            == submission.requestDigest.hexadecimalValue,
          model.planDigestAlgorithm
            == submission.plan.planDigest.algorithm.rawValue,
          model.planDigestValue
            == submission.plan.planDigest.hexadecimalValue,
          model.baseRevisionID
            == submission.plan.baseRevision.revisionID.description,
          model.candidateRevisionID == candidateRevision.revisionID.description,
          model.preparedDirectoryDigestAlgorithm
            == preparedDirectoryDigest.algorithm.rawValue,
          model.preparedDirectoryDigestValue
            == preparedDirectoryDigest.hexadecimalValue,
          model.preparedMutationCount == preparedMutationCount,
          model.stagingDigestAlgorithm == stagingDigest.algorithm.rawValue,
          model.stagingDigestValue == stagingDigest.hexadecimalValue,
          model.expectedDomainWriteCount == expectedDomainWriteCount,
          model.expectedProjectionNodeCount == expectedProjectionNodeCount else {
      throw .commitStagingConflict(
        operation: DesignDatabaseRuntimeOperationClaim.key(operation)
      )
    }
    guard model.stagedDomainWriteCount <= model.expectedDomainWriteCount,
          model.stagedProjectionNodeCount
            <= model.expectedProjectionNodeCount,
          let state = DesignCommitBuildIntentState(rawValue: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has invalid progress or state."
      )
    }
    if state == .prepared || state == .committed {
      guard model.stagedDomainWriteCount == model.expectedDomainWriteCount,
            model.stagedProjectionNodeCount
              == model.expectedProjectionNodeCount else {
        throw .persistedStateCorrupt(
          reason: "A terminal commit build intent is not fully staged."
        )
      }
    }
    let expectedProgressDigest = try progressDigest(
      stagingDigest: stagingDigest,
      stagedDomainWriteCount: model.stagedDomainWriteCount,
      stagedProjectionNodeCount: model.stagedProjectionNodeCount,
      state: state,
      using: digester
    )
    guard model.progressDigestAlgorithm
            == expectedProgressDigest.algorithm.rawValue,
          model.progressDigestValue
            == expectedProgressDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent progress digest does not match its state."
      )
    }
    return state
  }

  package static func validateStored(
    _ model: DesignCommitBuildIntentModel,
    operation: DesignDatabaseOperationReference,
    submission: DesignCommitSubmission,
    candidateRevision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentState {
    let stagingDigest: ContentDigest
    let preparedDirectoryDigest: ContentDigest
    do {
      preparedDirectoryDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.preparedDirectoryDigestAlgorithm
        ),
        hexadecimalValue: model.preparedDirectoryDigestValue
      )
      stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.stagingDigestAlgorithm
        ),
        hexadecimalValue: model.stagingDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has an invalid staging digest."
      )
    }
    return try validate(
      model,
      operation: operation,
      submission: submission,
      candidateRevision: candidateRevision,
      preparedDirectoryDigest: preparedDirectoryDigest,
      preparedMutationCount: model.preparedMutationCount,
      stagingDigest: stagingDigest,
      expectedDomainWriteCount: model.expectedDomainWriteCount,
      expectedProjectionNodeCount: model.expectedProjectionNodeCount,
      using: digester
    )
  }

  package static func validateStatus(
    _ model: DesignCommitBuildIntentModel,
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentState {
    guard model.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID
            == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue,
          model.requestDigestAlgorithm == requestDigest.algorithm.rawValue,
          model.requestDigestValue == requestDigest.hexadecimalValue,
          model.stagedDomainWriteCount <= model.expectedDomainWriteCount,
          model.stagedProjectionNodeCount
            <= model.expectedProjectionNodeCount,
          let state = DesignCommitBuildIntentState(rawValue: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent does not match its operation status."
      )
    }
    let stagingDigest: ContentDigest
    do {
      stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.stagingDigestAlgorithm
        ),
        hexadecimalValue: model.stagingDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has an invalid staging digest."
      )
    }
    let expectedProgressDigest = try progressDigest(
      stagingDigest: stagingDigest,
      stagedDomainWriteCount: model.stagedDomainWriteCount,
      stagedProjectionNodeCount: model.stagedProjectionNodeCount,
      state: state,
      using: digester
    )
    guard model.progressDigestAlgorithm
            == expectedProgressDigest.algorithm.rawValue,
          model.progressDigestValue
            == expectedProgressDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent status has an invalid progress digest."
      )
    }
    if state == .prepared || state == .committed {
      guard model.stagedDomainWriteCount == model.expectedDomainWriteCount,
            model.stagedProjectionNodeCount
              == model.expectedProjectionNodeCount else {
        throw .persistedStateCorrupt(
          reason: "A prepared commit build intent is not fully staged."
        )
      }
    }
    return state
  }

  package static func advanced(
    _ model: DesignCommitBuildIntentModel,
    stagedDomainWriteCount: UInt64? = nil,
    stagedProjectionNodeCount: UInt64? = nil,
    state: DesignCommitBuildIntentState? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentModel {
    var updated = model
    if let stagedDomainWriteCount {
      updated.stagedDomainWriteCount = stagedDomainWriteCount
    }
    if let stagedProjectionNodeCount {
      updated.stagedProjectionNodeCount = stagedProjectionNodeCount
    }
    if let state {
      updated.state = state.rawValue
    }
    return try updatingProgressDigest(updated, using: digester)
  }

  private static func updatingProgressDigest(
    _ model: DesignCommitBuildIntentModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignCommitBuildIntentModel {
    guard let state = DesignCommitBuildIntentState(rawValue: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has an unknown state."
      )
    }
    let stagingDigest: ContentDigest
    do {
      stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: model.stagingDigestAlgorithm
        ),
        hexadecimalValue: model.stagingDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A commit build intent has an invalid staging digest."
      )
    }
    let digest = try progressDigest(
      stagingDigest: stagingDigest,
      stagedDomainWriteCount: model.stagedDomainWriteCount,
      stagedProjectionNodeCount: model.stagedProjectionNodeCount,
      state: state,
      using: digester
    )
    var updated = model
    updated.progressDigestAlgorithm = digest.algorithm.rawValue
    updated.progressDigestValue = digest.hexadecimalValue
    return updated
  }

  private static func progressDigest(
    stagingDigest: ContentDigest,
    stagedDomainWriteCount: UInt64,
    stagedProjectionNodeCount: UInt64,
    state: DesignCommitBuildIntentState,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.CommitBuildProgress"
    )
    encoder.append(stagingDigest)
    encoder.append(stagedDomainWriteCount)
    encoder.append(stagedProjectionNodeCount)
    encoder.append(UInt64(state.rawValue))
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "The commit staging progress digest could not be computed: \(error)"
      )
    }
  }
}
