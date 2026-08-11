import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore

public actor DesignDatabaseRuntimeHandle:
  DesignDatabaseHandle,
  DesignDatabaseMaintenanceHandle,
  DesignDisjointMergePublishing
{
  public nonisolated let databaseID: DesignDatabaseID
  public nonisolated let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public nonisolated let featureCapabilities: DesignCapabilitySet
  public nonisolated let authorizationGrants: DesignDatabaseAuthorizationGrantSet
  public nonisolated let genesisRevision: DesignRevisionReference

  private let attachment: DesignDatabaseRuntimeAttachment
  private let authorizer: any DesignDatabaseAuthorizing
  private let lifecycle = DesignDatabaseRuntimeHandleLifecycle()
  private let snapshotRegistry = DesignDatabaseRuntimeSnapshotRegistry()
  private var nextSnapshotIdentifier: UInt64 = 0

  package init(
    descriptor: DesignDatabaseRuntimeCatalogDescriptor,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    authorizationGrants: DesignDatabaseAuthorizationGrantSet,
    authorizer: any DesignDatabaseAuthorizing,
    attachment: DesignDatabaseRuntimeAttachment
  ) {
    databaseID = descriptor.databaseID
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    featureCapabilities = descriptor.featureCapabilities
    self.authorizationGrants = authorizationGrants
    genesisRevision = descriptor.genesisRevision
    self.authorizer = authorizer
    self.attachment = attachment
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
    try await perform {
      try await self.resolveOperation(selector)
    }
  }

  public func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> any DesignReadSnapshot {
    try await perform {
      try await self.openSnapshotOperation(at: revision)
    }
  }

  public func diff(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionDiff {
    try await perform {
      try await self.diffOperation(request)
    }
  }

  public func assessDisjointMerge(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergeAssessment {
    try await perform {
      try await self.assessDisjointMergeOperation(request)
    }
  }

  public func publishDisjointMerge(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationResult {
    try await perform {
      try await self.publishDisjointMergeOperation(submission)
    }
  }

  private func publishDisjointMergeOperation(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationResult {
    try requireGrant(.proposeCandidate)
    guard submission.schemaVersion
            == DesignDisjointMergePublicationSubmission.currentSchemaVersion,
          submission.candidate.baseRevision.databaseID == databaseID,
          submission.candidate.parentRevisions.count == 2,
          Set(submission.candidate.parentRevisions).count == 2,
          submission.candidate.parentRevisions.allSatisfy({
            $0.databaseID == databaseID
          }),
          submission.validatedStateRevision.databaseID == databaseID else {
      throw .invalidMergeRequest(
        reason: "A merge publication must bind the current database and schema."
      )
    }
    let expectedRequestDigest = try DesignDisjointMergePublicationDigest
      .request(
        operationID: submission.operationID,
        candidate: submission.candidate,
        validatedStateRevision: submission.validatedStateRevision,
        validatedStateCommit: submission.validatedStateCommit,
        budget: submission.budget,
        using: SHA256ContentDigester()
      )
    guard expectedRequestDigest == submission.requestDigest else {
      throw .invalidMergeRequest(
        reason: "The merge-publication request digest does not match its canonical payload."
      )
    }
    let validatedCommitReceipt = try await validatedDisjointMergeCommitReceipt(
      submission
    )
    try await authorizer.authorize(
      .proposeCandidate,
      for: authorizationSubjectScopeID
    )
    let report = submission.candidate.resourceReport
    let request = try DesignDisjointMergeRequest(
      baseRevision: submission.candidate.baseRevision,
      leftRevision: submission.candidate.parentRevisions[0],
      rightRevision: submission.candidate.parentRevisions[1],
      budget: DesignDisjointMergeBudget(
        maximumFacetComparisonCount: report.maximumFacetComparisonCount,
        maximumAncestryRevisionCount: report.maximumAncestryRevisionCount
      )
    )
    let assessment = try await assessDisjointMergeOperation(request)
    let assessmentMatches: Bool
    switch assessment {
    case .requiresSemanticValidation(let current):
      assessmentMatches = current == submission.candidate
    case .conflict:
      assessmentMatches = false
    }
    return try await performStorage(operationID: submission.operationID) {
      try await self.attachment.publishDisjointMerge(
        submission,
        validatedCommitReceipt: validatedCommitReceipt,
        assessmentMatches: assessmentMatches,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  private func validatedDisjointMergeCommitReceipt(
    _ submission: DesignDisjointMergePublicationSubmission
  ) async throws(DesignDatabaseError) -> DesignCommitReceipt {
    let validatedCommit = submission.validatedStateCommit
    guard validatedCommit.operationID != submission.operationID else {
      throw .invalidMergeRequest(
        reason: "Merge publication and state validation require distinct operation identities."
      )
    }
    try validateMutationPlan(validatedCommit)
    let operation = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: validatedCommit.operationID
    )
    let status = try await commitStatusOperation(
      operation: operation,
      requestDigest: validatedCommit.requestDigest
    )
    guard case .committed(let receipt) = status,
          receipt.operation == operation,
          receipt.requestDigest == validatedCommit.requestDigest,
          receipt.planDigest == validatedCommit.plan.planDigest,
          receipt.baseRevision == validatedCommit.plan.baseRevision,
          receipt.candidateRevision == submission.validatedStateRevision,
          let parentIndex = submission.candidate.parentRevisions.firstIndex(
            of: validatedCommit.plan.baseRevision
          ) else {
      throw .invalidMergeRequest(
        reason: "The merge state is not bound to an exact committed one-parent validation operation."
      )
    }

    let rootsByFacet = Dictionary(
      uniqueKeysWithValues: submission.candidate.facetRoots.map {
        ($0.facetID, $0.digest)
      }
    )
    let segmentFacets = Set(validatedCommit.plan.segments.map(\.targetFacet))
    for segment in validatedCommit.plan.segments {
      guard rootsByFacet[segment.targetFacet] == segment.payloadDigest else {
        throw .invalidMergeRequest(
          reason: "A merge validation segment does not produce the assessed exact facet root."
        )
      }
    }
    let opposingChangedFacets = Set(
      parentIndex == 0
        ? submission.candidate.rightChangedFacetIDs
        : submission.candidate.leftChangedFacetIDs
    )
    guard opposingChangedFacets.isSubset(of: segmentFacets) else {
      throw .invalidMergeRequest(
        reason: "The merge validation commit did not validate every facet introduced onto its exact parent."
      )
    }
    if let dependencyRequirement = submission.candidate
      .semanticValidationRequirements.first(where: {
        $0.kind == .dependencyBinding
      }) {
      guard let update = validatedCommit.plan.dependencyLockUpdate,
            update.dependencyRootDigest
              == submission.candidate.dependencyRootDigest,
            update.semanticDependencyGraphDigest
              == submission.candidate.semanticDependencyGraphDigest,
            Set(dependencyRequirement.facetIDs).isSubset(
              of: segmentFacets
            ) else {
        throw .invalidMergeRequest(
          reason: "The merge validation commit did not revalidate every dependency-bound facet in the assessed dependency context."
        )
      }
    }
    return receipt
  }

  public func disjointMergePublicationStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationStatus {
    try await perform {
      try await self.disjointMergePublicationStatusOperation(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func disjointMergePublicationStatusOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergePublicationStatus {
    try requireGrant(.inspectOwnOperationOutcome)
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID
            == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    try await authorizer.authorize(
      .inspectOwnOperationOutcome,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: operation.operationID) {
      try await self.attachment.disjointMergePublicationStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func diffOperation(
    _ request: DesignRevisionDiffRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionDiff {
    try requireGrant(.read)
    try validateRevisionDatabase(request.fromRevision)
    try validateRevisionDatabase(request.toRevision)
    try await authorizer.authorize(.read, for: authorizationSubjectScopeID)

    let fromSnapshot = try await openSnapshotOperation(
      at: request.fromRevision
    )
    let toSnapshot: any DesignReadSnapshot
    do {
      toSnapshot = try await openSnapshotOperation(at: request.toRevision)
    } catch {
      _ = await fromSnapshot.close()
      throw error
    }
    do {
      let result = try DesignRevisionDiffer().diff(
        from: try stateDescriptor(fromSnapshot),
        to: try stateDescriptor(toSnapshot),
        budget: request.budget
      )
      _ = await toSnapshot.close()
      _ = await fromSnapshot.close()
      return result
    } catch {
      _ = await toSnapshot.close()
      _ = await fromSnapshot.close()
      throw error
    }
  }

  private func assessDisjointMergeOperation(
    _ request: DesignDisjointMergeRequest
  ) async throws(DesignDatabaseError) -> DesignDisjointMergeAssessment {
    try requireGrant(.read)
    try validateRevisionDatabase(request.baseRevision)
    try validateRevisionDatabase(request.leftRevision)
    try validateRevisionDatabase(request.rightRevision)
    try await authorizer.authorize(.read, for: authorizationSubjectScopeID)

    let baseSnapshot = try await openSnapshotOperation(
      at: request.baseRevision
    )
    let leftSnapshot: any DesignReadSnapshot
    do {
      leftSnapshot = try await openSnapshotOperation(at: request.leftRevision)
    } catch {
      _ = await baseSnapshot.close()
      throw error
    }
    let rightSnapshot: any DesignReadSnapshot
    do {
      rightSnapshot = try await openSnapshotOperation(at: request.rightRevision)
    } catch {
      _ = await leftSnapshot.close()
      _ = await baseSnapshot.close()
      throw error
    }

    do {
      let base = try stateDescriptor(baseSnapshot)
      let left = try stateDescriptor(leftSnapshot)
      let right = try stateDescriptor(rightSnapshot)
      let ancestry = try await ancestryResult(
        base: base,
        descendants: [left, right],
        maximumRevisionReadCount: request.budget.maximumAncestryRevisionCount
      )
      let assessment = try DesignDisjointMergeAssessor().assess(
        base: base,
        left: left,
        right: right,
        baseIsAncestorOfLeft: ancestry.results[0],
        baseIsAncestorOfRight: ancestry.results[1],
        ancestryRevisionReadCount: ancestry.revisionReadCount,
        budget: request.budget
      )
      _ = await rightSnapshot.close()
      _ = await leftSnapshot.close()
      _ = await baseSnapshot.close()
      return assessment
    } catch {
      _ = await rightSnapshot.close()
      _ = await leftSnapshot.close()
      _ = await baseSnapshot.close()
      throw error
    }
  }

  private func stateDescriptor(
    _ snapshot: any DesignReadSnapshot
  ) throws(DesignDatabaseError) -> DesignRevisionStateDescriptor {
    try DesignRevisionStateDescriptor(
      revision: snapshot.revision,
      parents: snapshot.parents,
      stateDigest: snapshot.stateDigest,
      designSchemaBundleDigest: snapshot.designSchemaBundleDigest,
      dependencyRootDigest: snapshot.dependencyRootDigest,
      semanticDependencyGraphDigest: snapshot.semanticDependencyGraphDigest,
      facetRoots: snapshot.facetRoots,
      directChangeRootDigest: snapshot.directChangeRootDigest
    )
  }

  private func ancestryResult(
    base: DesignRevisionStateDescriptor,
    descendants: [DesignRevisionStateDescriptor],
    maximumRevisionReadCount: UInt64
  ) async throws(DesignDatabaseError) -> (
    results: [Bool],
    revisionReadCount: UInt64
  ) {
    guard let endpointReadCount = UInt64(exactly: descendants.count + 1),
          endpointReadCount <= maximumRevisionReadCount else {
      throw .resourceExhausted(
        limit: maximumRevisionReadCount,
        requested: UInt64(exactly: descendants.count + 1) ?? UInt64.max
      )
    }
    var revisionReadCount = endpointReadCount
    var parentsByRevision: [
      DesignRevisionReference: [DesignRevisionReference]
    ] = [base.revision: base.parents]
    for descendant in descendants {
      parentsByRevision[descendant.revision] = descendant.parents
    }
    var results: [Bool] = []
    for descendant in descendants {
      if descendant.revision == base.revision {
        results.append(true)
        continue
      }
      var frontier = descendant.parents.sorted {
        $0.revisionID.description < $1.revisionID.description
      }
      var frontierIndex = 0
      var visited = Set<DesignRevisionReference>()
      var found = false
      while frontierIndex < frontier.count {
        let current = frontier[frontierIndex]
        frontierIndex += 1
        guard visited.insert(current).inserted else { continue }
        if current == base.revision {
          found = true
          break
        }
        let parents: [DesignRevisionReference]
        if let cached = parentsByRevision[current] {
          parents = cached
        } else {
          let (nextCount, overflow) = revisionReadCount.addingReportingOverflow(1)
          guard !overflow, nextCount <= maximumRevisionReadCount else {
            throw .resourceExhausted(
              limit: maximumRevisionReadCount,
              requested: overflow ? UInt64.max : nextCount
            )
          }
          let descriptor: DesignDatabaseRuntimeSnapshotDescriptor
          descriptor = try await performStorage(operationID: nil) {
            try await self.attachment.snapshotDescriptor(
              at: current,
              expectedDatabaseID: self.databaseID
            )
          }
          revisionReadCount = nextCount
          parentsByRevision[current] = descriptor.parents
          parents = descriptor.parents
        }
        frontier.append(
          contentsOf: parents.sorted {
            $0.revisionID.description < $1.revisionID.description
          }
        )
      }
      results.append(found)
    }
    return (results, revisionReadCount)
  }

  private func resolveOperation(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
    try requireGrant(.read)
    if case .exact(let revision) = selector {
      try validateRevisionDatabase(revision)
    }
    try await authorizer.authorize(.read, for: authorizationSubjectScopeID)
    return try await performStorage(operationID: nil) {
      try await self.attachment.resolve(
        selector,
        expectedDatabaseID: self.databaseID
      )
    }
  }

  public func submit(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseError) -> DesignCommitResult {
    try await perform {
      try await self.submitOperation(submission)
    }
  }

  private func submitOperation(
    _ submission: DesignCommitSubmission
  ) async throws(DesignDatabaseError) -> DesignCommitResult {
    try requireGrant(.proposeCandidate)
    try validateMutationPlan(submission)
    try await authorizer.authorize(
      .proposeCandidate,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: submission.operationID) {
      try await self.attachment.submit(
        submission,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  public func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitStatus {
    try await perform {
      try await self.commitStatusOperation(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func commitStatusOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitStatus {
    try requireGrant(.inspectOwnOperationOutcome)
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    try await authorizer.authorize(
      .inspectOwnOperationOutcome,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: operation.operationID) {
      try await self.attachment.commitStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func abandonCommit(
    _ request: DesignCommitAbandonmentRequest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentResult {
    try await perform {
      try await self.abandonCommitOperation(request)
    }
  }

  private func abandonCommitOperation(
    _ request: DesignCommitAbandonmentRequest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentResult {
    try requireGrant(.administer)
    guard request.targetOperation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: request.targetOperation.databaseID
      )
    }
    guard request.targetRequestDigest.algorithm == .sha256,
          request.evidenceDigest.algorithm == .sha256,
          request.requestDigest.algorithm == .sha256 else {
      throw .contentDigest(
        "Commit abandonment request identities must use SHA-256."
      )
    }
    let expectedDigest = try DesignCommitAbandonmentDigest.request(
      operationID: request.operationID,
      targetOperation: request.targetOperation,
      targetRequestDigest: request.targetRequestDigest,
      reason: request.reason,
      evidenceDigest: request.evidenceDigest,
      using: SHA256ContentDigester()
    )
    guard expectedDigest == request.requestDigest else {
      throw .contentDigest(
        "The commit abandonment request digest does not match its canonical payload."
      )
    }
    try await authorizer.authorize(
      .administer,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: request.operationID) {
      try await self.attachment.abandonCommit(
        request,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  public func commitAbandonmentStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentStatus {
    try await perform {
      try await self.commitAbandonmentStatusOperation(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func commitAbandonmentStatusOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentStatus {
    try requireGrant(.administer)
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard requestDigest.algorithm == .sha256 else {
      throw .contentDigest(
        "A commit abandonment status request must use a SHA-256 identity."
      )
    }
    try await authorizer.authorize(
      .administer,
      for: authorizationSubjectScopeID
    )
    return try await performMaintenanceStorage(operation: operation) {
      try await self.attachment.commitAbandonmentStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateResult {
    try await perform {
      try await self.compareAndSetReferenceOperation(request)
    }
  }

  private func compareAndSetReferenceOperation(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateResult {
    try requireGrant(.promoteReference)
    try validateRevisionDatabase(request.expectedRevision)
    try validateRevisionDatabase(request.desiredRevision)
    let expectedDigest = try DesignReferenceUpdateDigest.request(
      operationID: request.operationID,
      name: request.name,
      expectedGeneration: request.expectedGeneration,
      expectedRevision: request.expectedRevision,
      desiredRevision: request.desiredRevision,
      using: SHA256ContentDigester()
    )
    guard request.requestDigest == expectedDigest else {
      throw .contentDigest(
        "The reference update request digest does not match its canonical payload."
      )
    }
    try await authorizer.authorize(
      .promoteReference,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: request.operationID) {
      try await self.attachment.compareAndSetReference(
        request,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  public func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateStatus {
    try await perform {
      try await self.referenceStatusOperation(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func referenceStatusOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateStatus {
    try requireGrant(.inspectOwnOperationOutcome)
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    try await authorizer.authorize(
      .inspectOwnOperationOutcome,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: operation.operationID) {
      try await self.attachment.referenceStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  public func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try await perform {
      try await self.retainOperation(request)
    }
  }

  private func retainOperation(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try requireGrant(.retain)
    try validateRevisionDatabase(request.revision)
    let expectedDigest = try DesignRevisionRetentionDigest.retainingRequest(
      operationID: request.operationID,
      claimID: request.claimID,
      revision: request.revision,
      reason: request.reason,
      evidenceDigest: request.evidenceDigest,
      using: SHA256ContentDigester()
    )
    guard request.requestDigest == expectedDigest else {
      throw .contentDigest(
        "The retention request digest does not match its canonical payload."
      )
    }
    try await authorizer.authorize(.retain, for: authorizationSubjectScopeID)
    return try await performStorage(operationID: request.operationID) {
      try await self.attachment.retain(
        request,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  public func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try await perform {
      try await self.releaseRetentionOperation(request)
    }
  }

  private func releaseRetentionOperation(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try requireGrant(.retain)
    try validateRevisionDatabase(request.expectedRevision)
    let expectedDigest = try DesignRevisionRetentionDigest.releasingRequest(
      operationID: request.operationID,
      claimID: request.claimID,
      expectedRevision: request.expectedRevision,
      expectedGeneration: request.expectedGeneration,
      using: SHA256ContentDigester()
    )
    guard request.requestDigest == expectedDigest else {
      throw .contentDigest(
        "The retention release request digest does not match its canonical payload."
      )
    }
    try await authorizer.authorize(.retain, for: authorizationSubjectScopeID)
    return try await performStorage(operationID: request.operationID) {
      try await self.attachment.releaseRetention(
        request,
        databaseID: self.databaseID,
        authorizationSubjectScopeID: self.authorizationSubjectScopeID
      )
    }
  }

  public func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionStatus {
    try await perform {
      try await self.retentionStatusOperation(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func retentionStatusOperation(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionStatus {
    try requireGrant(.inspectOwnOperationOutcome)
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    guard operation.authorizationSubjectScopeID == authorizationSubjectScopeID else {
      throw .unauthorized(
        grant: .inspectOwnOperationOutcome,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
    try await authorizer.authorize(
      .inspectOwnOperationOutcome,
      for: authorizationSubjectScopeID
    )
    return try await performStorage(operationID: operation.operationID) {
      try await self.attachment.retentionStatus(
        operation: operation,
        requestDigest: requestDigest
      )
    }
  }

  private func openSnapshotOperation(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> any DesignReadSnapshot {
    try requireGrant(.read)
    try validateRevisionDatabase(revision)
    try await authorizer.authorize(.read, for: authorizationSubjectScopeID)
    let lease = try await performStorage(operationID: nil) {
      try await self.attachment.snapshotLeaseCoordinator.registerPending(
        revision: revision
      )
    }
    do {
      let descriptor = try await performStorage(operationID: nil) {
        try await self.attachment.snapshotDescriptor(
          at: revision,
          expectedDatabaseID: self.databaseID
        )
      }
      let databaseContext = try await performStorage(operationID: nil) {
        try await self.attachment.context()
      }
      let identifier = nextSnapshotIdentifier
      let (nextIdentifier, overflow) = identifier.addingReportingOverflow(1)
      guard !overflow else {
        throw DesignDatabaseError.generationExhausted(
          kind: "runtime snapshot"
        )
      }
      nextSnapshotIdentifier = nextIdentifier
      try await performStorage(operationID: nil) {
        try await self.attachment.snapshotLeaseCoordinator.activate(
          lease,
          materializationBindings: descriptor.materializationBindings
        )
      }
      let snapshot = DesignDatabaseRuntimeSnapshot(
        identifier: identifier,
        revision: descriptor.revision,
        parents: descriptor.parents,
        stateDigest: descriptor.stateDigest,
        designSchemaBundle: descriptor.designSchemaBundle,
        designSchemaBundleDigest: descriptor.designSchemaBundleDigest,
        directDependencyLock: descriptor.directDependencyLock,
        dependencyRootDigest: descriptor.dependencyRootDigest,
        semanticDependencyGraphDigest: descriptor.semanticDependencyGraphDigest,
        facetRoots: descriptor.facetRoots,
        directChangeRootDigest: descriptor.directChangeRootDigest,
        projectionSemantics: descriptor.projectionSemantics,
        projectionDescriptorDigests: descriptor.projectionDescriptorDigests,
        materializationBindings: descriptor.materializationBindings,
        snapshotLease: lease,
        context: databaseContext,
        decodedPageCache: attachment.decodedProjectionPageCache,
        leaseCoordinator: attachment.snapshotLeaseCoordinator,
        registry: snapshotRegistry
      )
      try await snapshotRegistry.register(snapshot, identifiedBy: identifier)
      return snapshot
    } catch let error as DesignDatabaseError {
      await attachment.snapshotLeaseCoordinator.release(lease)
      throw error
    } catch {
      await attachment.snapshotLeaseCoordinator.release(lease)
      throw .persistence(
        "Snapshot lease activation returned an unexpected failure: \(error)"
      )
    }
  }

  public func close() async -> DesignDatabaseTermination {
    guard await lifecycle.beginClose() else { return .alreadyClosed }
    await snapshotRegistry.closeAll()
    let termination: DesignDatabaseTermination
    switch await attachment.close() {
    case .closed:
      termination = .closed
    case .alreadyClosed:
      termination = .alreadyClosed
    }
    await lifecycle.finishClose()
    return termination
  }

  private func perform<Result: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Result
  ) async throws(DesignDatabaseError) -> Result {
    try await lifecycle.perform(operation)
  }

  private func performStorage<Result: Sendable>(
    operationID: DesignDatabaseOperationID?,
    _ operation: nonisolated(nonsending) () async throws -> Result
  ) async throws(DesignDatabaseError) -> Result {
    do {
      return try await DesignDatabaseRuntimeStorageSecurity
        .withAuthorizedAccess(operation)
    } catch let error as DesignDatabaseRuntimeError {
      throw map(error, operationID: operationID)
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .persistence(
        "The storage authorization boundary returned an unexpected failure: \(error)"
      )
    }
  }

  private func performMaintenanceStorage<Result: Sendable>(
    operation: DesignDatabaseOperationReference,
    _ body: nonisolated(nonsending) () async throws -> Result
  ) async throws(DesignDatabaseError) -> Result {
    do {
      return try await DesignDatabaseRuntimeStorageSecurity
        .withAuthorizedAccess(body)
    } catch DesignDatabaseRuntimeError
      .commitAbandonmentIdempotencyConflict {
      throw .idempotencyConflict(operation: operation)
    } catch let error as DesignDatabaseRuntimeError {
      throw map(error, operationID: operation.operationID)
    } catch let error as DesignDatabaseError {
      throw error
    } catch {
      throw .persistence(
        "The maintenance storage authorization boundary returned an unexpected failure: \(error)"
      )
    }
  }

  private func requireGrant(
    _ grant: DesignDatabaseAuthorizationGrant
  ) throws(DesignDatabaseError) {
    guard authorizationGrants.contains(grant) else {
      throw .unauthorized(
        grant: grant,
        subjectScopeID: authorizationSubjectScopeID
      )
    }
  }

  private func validateRevisionDatabase(
    _ revision: DesignRevisionReference?
  ) throws(DesignDatabaseError) {
    guard let revision else { return }
    guard revision.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: revision.databaseID
      )
    }
  }

  private func validateMutationPlan(
    _ submission: DesignCommitSubmission
  ) throws(DesignDatabaseError) {
    let plan = submission.plan
    guard plan.schemaVersion == DesignMutationPlan.currentSchemaVersion else {
      throw .invalidMutationPlan(reason: "The mutation-plan schema is unsupported.")
    }
    guard plan.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: plan.databaseID
      )
    }
    guard plan.baseRevision.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: plan.baseRevision.databaseID
      )
    }
    guard !plan.segments.isEmpty || plan.dependencyLockUpdate != nil else {
      throw .invalidMutationPlan(
        reason: "A mutation plan must contain a domain segment or one exact dependency-lock update."
      )
    }
    guard plan.budget.maximumSegmentCount > 0,
          plan.budget.maximumPayloadByteCount > 0,
          plan.budget.maximumPreparedWriteCount > 0,
          plan.budget.maximumValidationReadCount > 0 else {
      throw .invalidMutationPlan(
        reason: "Every mutation-plan budget must be greater than zero."
      )
    }
    guard plan.segments.count <= Int(plan.budget.maximumSegmentCount) else {
      throw .resourceExhausted(
        limit: UInt64(plan.budget.maximumSegmentCount),
        requested: UInt64(plan.segments.count)
      )
    }
    let requiredDigests = [
      plan.designSchemaBundleDigest,
      plan.dependencyRootDigest,
      plan.semanticDependencyGraphDigest,
      plan.sourceEvidenceDigest,
      plan.planDigest,
      submission.requestDigest,
    ]
    guard requiredDigests.allSatisfy({ $0.algorithm == .sha256 }) else {
      throw .invalidMutationPlan(
        reason: "Every mutation-plan identity must use SHA-256."
      )
    }
    if let dependencyUpdate = plan.dependencyLockUpdate {
      let computedRoot = try DesignDependencyLockDigest.root(
        dependencyUpdate.replacement,
        using: SHA256ContentDigester()
      )
      guard computedRoot == dependencyUpdate.dependencyRootDigest,
            dependencyUpdate.semanticDependencyGraphDigest.algorithm == .sha256 else {
        throw .invalidMutationPlan(
          reason: "The dependency-lock update does not match its canonical root identity."
        )
      }
    }

    var segmentIDs = Set<DesignMutationPlanSegmentID>()
    var totalPayloadBytes: UInt64 = 0
    var expectedWrites: UInt64 = 0
    let digester = SHA256ContentDigester()
    for segment in plan.segments {
      guard !segment.adapterVersion.isEmpty,
            !segment.payload.isEmpty,
            segment.expectedWriteCount > 0 else {
        throw .invalidMutationPlan(
          reason: "Every mutation-plan segment must declare an adapter version, payload, and expected write count."
        )
      }
      guard segmentIDs.insert(segment.id).inserted else {
        throw .invalidMutationPlan(
          reason: "Mutation-plan segment identifiers must be unique."
        )
      }
      guard segment.payloadDigest.algorithm == .sha256,
            try DesignMutationPlanDigest.payload(
              segment.payload,
              using: digester
            ) == segment.payloadDigest else {
        throw .invalidMutationPlan(
          reason: "A mutation-plan segment payload digest does not match its bytes."
        )
      }
      let (nextPayloadBytes, payloadOverflow) = totalPayloadBytes
        .addingReportingOverflow(UInt64(segment.payload.count))
      let (nextExpectedWrites, writeOverflow) = expectedWrites
        .addingReportingOverflow(segment.expectedWriteCount)
      guard !payloadOverflow, !writeOverflow else {
        throw .invalidMutationPlan(reason: "Mutation-plan budget accounting overflowed.")
      }
      totalPayloadBytes = nextPayloadBytes
      expectedWrites = nextExpectedWrites
    }
    guard totalPayloadBytes <= plan.budget.maximumPayloadByteCount else {
      throw .resourceExhausted(
        limit: plan.budget.maximumPayloadByteCount,
        requested: totalPayloadBytes
      )
    }
    guard expectedWrites <= plan.budget.maximumPreparedWriteCount else {
      throw .resourceExhausted(
        limit: plan.budget.maximumPreparedWriteCount,
        requested: expectedWrites
      )
    }
    let expectedPlanDigest = try DesignMutationPlanDigest.plan(
      databaseID: plan.databaseID,
      baseRevision: plan.baseRevision,
      designSchemaBundleDigest: plan.designSchemaBundleDigest,
      dependencyRootDigest: plan.dependencyRootDigest,
      semanticDependencyGraphDigest: plan.semanticDependencyGraphDigest,
      sourceEvidenceDigest: plan.sourceEvidenceDigest,
      budget: plan.budget,
      segments: plan.segments,
      dependencyLockUpdate: plan.dependencyLockUpdate,
      using: digester
    )
    guard expectedPlanDigest == plan.planDigest else {
      throw .invalidMutationPlan(
        reason: "The mutation-plan digest does not match its canonical payload."
      )
    }
    let expectedRequestDigest = try DesignMutationPlanDigest.request(
      operationID: submission.operationID,
      planDigest: plan.planDigest,
      using: digester
    )
    guard expectedRequestDigest == submission.requestDigest else {
      throw .invalidMutationPlan(
        reason: "The commit request digest does not match its canonical payload."
      )
    }
  }

  private func map(
    _ error: DesignDatabaseRuntimeError,
    operationID: DesignDatabaseOperationID?
  ) -> DesignDatabaseError {
    switch error {
    case .commitAbandonmentIdempotencyConflict:
      guard let operationID else {
        return .corruption(
          "A commit abandonment idempotency conflict omitted its operation."
        )
      }
      return .idempotencyConflict(
        operation: DesignDatabaseOperationReference(
          databaseID: databaseID,
          authorizationSubjectScopeID: authorizationSubjectScopeID,
          operationID: operationID
        )
      )
    case .commitIdempotencyConflict, .commitStagingConflict,
         .disjointMergeIdempotencyConflict:
      guard let operationID else {
        return .corruption("A commit idempotency conflict omitted its operation.")
      }
      return .idempotencyConflict(
        operation: DesignDatabaseOperationReference(
          databaseID: databaseID,
          authorizationSubjectScopeID: authorizationSubjectScopeID,
          operationID: operationID
        )
      )
    case .referenceIdempotencyConflict:
      guard let operationID else {
        return .corruption("A reference idempotency conflict omitted its operation.")
      }
      return .idempotencyConflict(
        operation: DesignDatabaseOperationReference(
          databaseID: databaseID,
          authorizationSubjectScopeID: authorizationSubjectScopeID,
          operationID: operationID
        )
      )
    case .generationExhausted(let kind):
      return .generationExhausted(kind: kind)
    case .namedReferenceNotFound(let rawValue):
      do {
        return .referenceNotFound(try DesignReferenceName(rawValue: rawValue))
      } catch {
        return .corruption("Runtime returned a malformed reference name.")
      }
    case .revisionNotFound(let rawValue):
      do {
        return .revisionNotFound(
          DesignRevisionReference(
            databaseID: databaseID,
            revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
          )
        )
      } catch {
        return .corruption("Runtime returned a malformed revision identity.")
      }
    case .revisionDeleting(let rawValue):
      do {
        return .revisionDeleting(
          DesignRevisionReference(
            databaseID: databaseID,
            revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
          )
        )
      } catch {
        return .corruption("Runtime returned a malformed deleting revision identity.")
      }
    case .revisionCollected(let rawValue):
      do {
        return .revisionCollected(
          DesignRevisionReference(
            databaseID: databaseID,
            revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
          )
        )
      } catch {
        return .corruption("Runtime returned a malformed collected revision identity.")
      }
    case .persistedStateCorrupt(let reason):
      return .corruption(reason)
    case .attachmentClosed:
      return .closed
    case .referenceTransactionFailed(let reason):
      return .persistence(reason)
    case .retentionTransactionFailed(let reason):
      return .persistence(reason)
    case .commitTransactionFailed(let reason):
      return .persistence(reason)
    case .commitAbandonmentTransactionFailed(let reason):
      return .persistence(reason)
    default:
      return .persistence(String(describing: error))
    }
  }
}
