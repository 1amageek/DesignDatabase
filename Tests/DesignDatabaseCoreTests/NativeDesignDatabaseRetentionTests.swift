import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import DesignDatabaseCore
import DesignDatabaseNative
import Foundation
import Testing

@Suite
struct NativeDesignDatabaseRetentionTests {
  @Test
  func retentionLifecycleIsIdempotentAndLeavesPermanentTombstone() async throws {
    let fixture = try await makeDatabase()
    let root = try await fixture.database.resolve(.named(.main))
    let claimID = try DesignRevisionRetentionID(rawValue: "release-bundle-1")
    let evidenceDigest = try digest(repeating: "a")
    let retainRequest = try makeRetainRequest(
      operation: "retain-1",
      claimID: claimID,
      revision: root,
      reason: "release-bundle",
      evidenceDigest: evidenceDigest
    )

    let active = try appliedReceipt(try await fixture.database.retain(retainRequest))
    #expect(active.claimID == claimID)
    #expect(active.revision == root)
    #expect(active.generation == 1)
    #expect(active.state == .active)
    #expect(try await fixture.database.retain(retainRequest) == .applied(active))

    let conflictingRequest = try makeRetainRequest(
      operation: "retain-1",
      claimID: claimID,
      revision: root,
      reason: "different-reason",
      evidenceDigest: evidenceDigest
    )
    let conflict = try rejectedReason(
      try await fixture.database.retain(conflictingRequest)
    )
    #expect(conflict == .operationRequestConflict)
    #expect(
      try rejectedReason(try await fixture.database.retain(
        try makeRetainRequest(
          operation: "retain-active-duplicate",
          claimID: claimID,
          revision: root,
          reason: "release-bundle",
          evidenceDigest: evidenceDigest
        )
      )) == .claimAlreadyActive
    )
    #expect(
      try rejectedReason(try await fixture.database.releaseRetention(
        try makeReleaseRequest(
          operation: "release-wrong-generation",
          claimID: claimID,
          revision: root,
          expectedGeneration: active.generation + 1
        )
      )) == .generationMismatch(actual: active.generation)
    )
    let wrongRevision = DesignRevisionReference(
      databaseID: root.databaseID,
      revisionID: DesignRevisionID(high: 0xBAD, low: 0xF00D)
    )
    #expect(
      try rejectedReason(try await fixture.database.releaseRetention(
        try makeReleaseRequest(
          operation: "release-wrong-revision",
          claimID: claimID,
          revision: wrongRevision,
          expectedGeneration: active.generation
        )
      )) == .revisionMismatch
    )
    #expect(
      try rejectedReason(try await fixture.database.releaseRetention(
        try makeReleaseRequest(
          operation: "release-unavailable",
          claimID: DesignRevisionRetentionID(rawValue: "unavailable-claim"),
          revision: root,
          expectedGeneration: 1
        )
      )) == .claimUnavailable
    )

    let releaseRequest = try makeReleaseRequest(
      operation: "release-1",
      claimID: claimID,
      revision: root,
      expectedGeneration: active.generation
    )
    let released = try appliedReceipt(
      try await fixture.database.releaseRetention(releaseRequest)
    )
    #expect(released.generation == 2)
    #expect(released.state == .released)
    #expect(released.reachabilityGeneration > active.reachabilityGeneration)
    #expect(
      try await fixture.database.releaseRetention(releaseRequest)
        == .applied(released)
    )

    let delayedCreate = try makeRetainRequest(
      operation: "retain-2",
      claimID: claimID,
      revision: root,
      reason: "release-bundle",
      evidenceDigest: evidenceDigest
    )
    #expect(
      try rejectedReason(try await fixture.database.retain(delayedCreate))
        == .claimPermanentlyReleased
    )

    let retainOperation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: retainRequest.operationID
    )
    #expect(
      try await fixture.database.retentionStatus(
        operation: retainOperation,
        requestDigest: retainRequest.requestDigest
      ) == .applied(active)
    )
    let releaseOperation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: releaseRequest.operationID
    )
    #expect(
      try await fixture.database.retentionStatus(
        operation: releaseOperation,
        requestDigest: releaseRequest.requestDigest
      ) == .applied(released)
    )
    try await fixture.database.close()
  }

  @Test
  func mutationAndOutcomeInspectionGrantsAreRevalidatedIndependently() async throws {
    let fixture = try await makeDatabase()
    let root = try await fixture.database.resolve(.named(.main))
    let request = try makeRetainRequest(
      operation: "retain-revocation",
      claimID: try DesignRevisionRetentionID(rawValue: "run-1"),
      revision: root,
      reason: "active-run",
      evidenceDigest: try digest(repeating: "b")
    )
    let receipt = try appliedReceipt(try await fixture.database.retain(request))
    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: request.operationID
    )

    await fixture.authority.replaceGrants(
      DesignDatabaseAuthorizationGrantSet([.read, .retain]),
      for: fixture.scopeID
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      )
    }
    #expect(try await fixture.database.retain(request) == .applied(receipt))

    await fixture.authority.replaceGrants(
      DesignDatabaseAuthorizationGrantSet([
        .read,
        .inspectOwnOperationOutcome,
      ]),
      for: fixture.scopeID
    )
    #expect(
      try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .applied(receipt)
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await fixture.database.releaseRetention(
        try makeReleaseRequest(
          operation: "release-revoked",
          claimID: request.claimID,
          revision: root,
          expectedGeneration: receipt.generation
        )
      )
    }
    try await fixture.database.close()
  }

  @Test
  func committedOutcomeIsReconciledAfterPersistenceResponseIsLost() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let root = try await fixture.database.resolve(.named(.main))
    let request = try makeRetainRequest(
      operation: "retain-lost-response",
      claimID: try DesignRevisionRetentionID(rawValue: "dependency-1"),
      revision: root,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "c")
    )
    await persistence.failNextPersistAfterCommit()

    let receipt = try appliedReceipt(try await fixture.database.retain(request))
    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: request.operationID
    )
    #expect(
      try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .applied(receipt)
    )
    try await fixture.database.close()
  }

  @Test
  func releaseAndRejectionOutcomesReconcileAfterPersistenceResponseLoss() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let root = try await fixture.database.resolve(.named(.main))
    let claimID = try DesignRevisionRetentionID(rawValue: "lost-release")
    let active = try appliedReceipt(try await fixture.database.retain(
      try makeRetainRequest(
        operation: "retain-for-lost-release",
        claimID: claimID,
        revision: root,
        reason: "dependency",
        evidenceDigest: try digest(repeating: "8")
      )
    ))
    let release = try makeReleaseRequest(
      operation: "release-lost-response",
      claimID: claimID,
      revision: root,
      expectedGeneration: active.generation
    )
    await persistence.failNextPersistAfterCommit()
    let released = try appliedReceipt(
      try await fixture.database.releaseRetention(release)
    )
    #expect(released.state == .released)

    let unavailableRevision = DesignRevisionReference(
      databaseID: root.databaseID,
      revisionID: DesignRevisionID(high: 0xDEAD, low: 0xBEEF)
    )
    let rejection = try makeRetainRequest(
      operation: "rejection-lost-response",
      claimID: try DesignRevisionRetentionID(rawValue: "missing-revision"),
      revision: unavailableRevision,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "9")
    )
    await persistence.failNextPersistAfterCommit()
    #expect(
      try rejectedReason(try await fixture.database.retain(rejection))
        == .revisionNotFound
    )
    let rejectionOperation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: rejection.operationID
    )
    guard case .rejected(let persistedRejection) = try await fixture.database.retentionStatus(
      operation: rejectionOperation,
      requestDigest: rejection.requestDigest
    ) else {
      throw RetentionTestError.expectedRejected
    }
    #expect(persistedRejection.reason == .revisionNotFound)
    try await fixture.database.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func reconciliationBlocksMutationAndReportsTheMatchingOperationInProgress() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let root = try await fixture.database.resolve(.named(.main))
    let request = try makeRetainRequest(
      operation: "retain-suspended-reconciliation",
      claimID: try DesignRevisionRetentionID(rawValue: "suspended-claim"),
      revision: root,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "1")
    )
    let competingRequest = try makeRetainRequest(
      operation: "retain-competing",
      claimID: try DesignRevisionRetentionID(rawValue: "competing-claim"),
      revision: root,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "2")
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: request.operationID
    )
    await persistence.failAfterCommitAndSuspendNextReconciliationLoad()

    let retained = Task {
      try await fixture.database.retain(request)
    }
    await persistence.waitUntilReconciliationLoadIsSuspended()

    #expect(
      try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .inProgress
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await fixture.database.retain(competingRequest)
    }
    await #expect(throws: DesignDatabaseError.self) {
      try await fixture.database.close()
    }

    await persistence.resumeReconciliationLoad()
    let receipt = try appliedReceipt(try await retained.value)
    #expect(
      try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .applied(receipt)
    )
    _ = try appliedReceipt(try await fixture.database.retain(competingRequest))
    try await fixture.database.close()
  }

  @Test
  func unresolvedPersistenceFailureIsNotReportedAsSuccess() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let root = try await fixture.database.resolve(.named(.main))
    let request = try makeRetainRequest(
      operation: "retain-unknown",
      claimID: try DesignRevisionRetentionID(rawValue: "unknown-claim"),
      revision: root,
      reason: "active-run",
      evidenceDigest: try digest(repeating: "f")
    )
    await persistence.failNextPersistBeforeCommitAndHideReconciliation()

    let submission = try await fixture.database.retain(request)
    guard case .outcomeUnknown(let unknown) = submission else {
      throw RetentionTestError.expectedUnknown
    }
    let operation = DesignDatabaseOperationReference(
      databaseID: fixture.database.databaseID,
      authorizationSubjectScopeID: fixture.scopeID,
      operationID: request.operationID
    )
    #expect(unknown.operation == operation)
    #expect(
      try await fixture.database.retentionStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .notRecorded
    )
    _ = try appliedReceipt(try await fixture.database.retain(request))
    try await fixture.database.close()
  }

  @Test
  func foreignAndStalePersistenceImagesFailClosedDuringReconciliation() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let foreignPersistence = ReconciliationPersistence()
    let foreignFixture = try await makeDatabase(persistence: foreignPersistence)
    let foreignImage = try #require(await foreignPersistence.snapshotImage())
    let root = try await fixture.database.resolve(.named(.main))
    let foreignRequest = try makeRetainRequest(
      operation: "retain-foreign-image",
      claimID: try DesignRevisionRetentionID(rawValue: "foreign-image"),
      revision: root,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "3")
    )
    await persistence.failBeforeCommitAndReturnOnNextLoad(foreignImage)

    do {
      _ = try await fixture.database.retain(foreignRequest)
      Issue.record("Foreign database image was accepted during reconciliation.")
    } catch let error {
      guard case .corruption = error else {
        Issue.record("Expected corruption for foreign image, received \(error).")
        try await foreignFixture.database.close()
        return
      }
    }
    #expect(fixture.database.databaseID != foreignFixture.database.databaseID)
    try await fixture.database.close()
    try await foreignFixture.database.close()

    let stalePersistence = ReconciliationPersistence()
    let staleFixture = try await makeDatabase(persistence: stalePersistence)
    let staleImage = try #require(await stalePersistence.snapshotImage())
    let staleRoot = try await staleFixture.database.resolve(.named(.main))
    _ = try appliedReceipt(try await staleFixture.database.retain(
      try makeRetainRequest(
        operation: "retain-before-stale",
        claimID: try DesignRevisionRetentionID(rawValue: "before-stale"),
        revision: staleRoot,
        reason: "dependency",
        evidenceDigest: try digest(repeating: "4")
      )
    ))
    let staleRequest = try makeRetainRequest(
      operation: "retain-stale-image",
      claimID: try DesignRevisionRetentionID(rawValue: "stale-image"),
      revision: staleRoot,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "5")
    )
    await stalePersistence.failBeforeCommitAndReturnOnNextLoad(staleImage)

    do {
      _ = try await staleFixture.database.retain(staleRequest)
      Issue.record("Stale database image was accepted during reconciliation.")
    } catch let error {
      guard case .corruption = error else {
        Issue.record("Expected corruption for stale image, received \(error).")
        try await staleFixture.database.close()
        return
      }
    }
    try await staleFixture.database.close()
  }

  @Test
  func malformedClaimLineageAndRejectionDigestAreRejectedOnOpen() async throws {
    let persistence = ReconciliationPersistence()
    let fixture = try await makeDatabase(persistence: persistence)
    let root = try await fixture.database.resolve(.named(.main))
    _ = try appliedReceipt(try await fixture.database.retain(
      try makeRetainRequest(
        operation: "retain-lineage",
        claimID: try DesignRevisionRetentionID(rawValue: "lineage"),
        revision: root,
        reason: "dependency",
        evidenceDigest: try digest(repeating: "6")
      )
    ))
    let retainedImage = try #require(await persistence.snapshotImage())
    let orphanedImage = copyImage(
      retainedImage,
      retentionClaims: retainedImage.retentionClaims,
      operationRecords: [:]
    )
    expectCorruption {
      _ = try NativeDesignDatabase(
        image: orphanedImage,
        validators: [],
        authorizationSubjectScopeID: fixture.scopeID,
        authorizationGrants: DesignDatabaseAuthorizationGrantSet(
          DesignDatabaseAuthorizationGrant.allCases
        ),
        authorizer: fixture.authority
      )
    }
    let activeClaim = try #require(retainedImage.retentionClaims.values.first)
    var invalidClaims = retainedImage.retentionClaims
    invalidClaims[activeClaim.claimID] = DesignRevisionRetentionClaim(
      claimID: activeClaim.claimID,
      revision: activeClaim.revision,
      ownerSubjectScopeID: activeClaim.ownerSubjectScopeID,
      reason: activeClaim.reason,
      evidenceDigest: activeClaim.evidenceDigest,
      generation: 3,
      state: .released
    )
    let generationThreeImage = copyImage(
      retainedImage,
      retentionClaims: invalidClaims,
      operationRecords: retainedImage.operationRecords
    )
    expectCorruption {
      _ = try NativeDesignDatabase(
        image: generationThreeImage,
        validators: [],
        authorizationSubjectScopeID: fixture.scopeID,
        authorizationGrants: DesignDatabaseAuthorizationGrantSet(
          DesignDatabaseAuthorizationGrant.allCases
        ),
        authorizer: fixture.authority
      )
    }
    try await fixture.database.close()

    let rejectionPersistence = ReconciliationPersistence()
    let rejectionFixture = try await makeDatabase(persistence: rejectionPersistence)
    let rejectionRoot = try await rejectionFixture.database.resolve(.named(.main))
    let unavailableRevision = DesignRevisionReference(
      databaseID: rejectionRoot.databaseID,
      revisionID: DesignRevisionID(high: UInt64.max, low: UInt64.max)
    )
    let rejectedRequest = try makeRetainRequest(
      operation: "retain-rejected",
      claimID: try DesignRevisionRetentionID(rawValue: "rejected"),
      revision: unavailableRevision,
      reason: "dependency",
      evidenceDigest: try digest(repeating: "7")
    )
    #expect(
      try rejectedReason(try await rejectionFixture.database.retain(rejectedRequest))
        == .revisionNotFound
    )
    let rejectionImage = try #require(await rejectionPersistence.snapshotImage())
    let operation = DesignDatabaseOperationReference(
      databaseID: rejectionFixture.database.databaseID,
      authorizationSubjectScopeID: rejectionFixture.scopeID,
      operationID: rejectedRequest.operationID
    )
    let record = try #require(rejectionImage.operationRecords[operation])
    guard case .retentionRejected(let rejection) = record.outcome else {
      throw RetentionTestError.expectedRejected
    }
    let tamperedRejection = DesignRevisionRetentionRejection(
      operation: rejection.operation,
      requestDigest: rejection.requestDigest,
      reason: .claimUnavailable,
      outcomeDigest: rejection.outcomeDigest
    )
    var tamperedRecords = rejectionImage.operationRecords
    tamperedRecords[operation] = DesignDatabaseOperationRecord(
      operation: operation,
      requestDigest: record.requestDigest,
      outcome: .retentionRejected(tamperedRejection)
    )
    let tamperedImage = copyImage(
      rejectionImage,
      retentionClaims: rejectionImage.retentionClaims,
      operationRecords: tamperedRecords
    )
    expectCorruption {
      _ = try NativeDesignDatabase(
        image: tamperedImage,
        validators: [],
        authorizationSubjectScopeID: rejectionFixture.scopeID,
        authorizationGrants: DesignDatabaseAuthorizationGrantSet(
          DesignDatabaseAuthorizationGrant.allCases
        ),
        authorizer: rejectionFixture.authority
      )
    }
    try await rejectionFixture.database.close()
  }

  @Test
  func callerSuppliedRequestDigestMustMatchCanonicalPayload() async throws {
    let fixture = try await makeDatabase()
    let root = try await fixture.database.resolve(.named(.main))
    let request = DesignRevisionRetentionRequest(
      operationID: try DesignDatabaseOperationID(rawValue: "retain-tampered"),
      claimID: try DesignRevisionRetentionID(rawValue: "tampered"),
      revision: root,
      reason: try DesignRevisionRetentionReason(rawValue: "active-run"),
      evidenceDigest: try digest(repeating: "d"),
      requestDigest: try digest(repeating: "e")
    )

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await fixture.database.retain(request)
    }
    try await fixture.database.close()
  }

  private func makeDatabase(
    persistence: (any DesignDatabasePersisting)? = nil
  ) async throws -> DatabaseFixture {
    let scopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x444442,
      low: 0x524554
    )
    let grants = DesignDatabaseAuthorizationGrantSet(
      DesignDatabaseAuthorizationGrant.allCases
    )
    let authority = NativeDesignDatabaseAuthorizationAuthority(
      grantsBySubjectScope: [scopeID: grants]
    )
    let database = try await NativeDesignDatabaseProvider(
      authorizationSubjectScopeID: scopeID,
      requestedAuthorization: grants,
      authorizer: authority,
      persistence: persistence
    ).create(
      DesignReferenceDatabaseCreateRequest(
        schemas: [],
        capabilities: DesignCapabilitySet([])
      )
    )
    return DatabaseFixture(
      database: database,
      authority: authority,
      scopeID: scopeID
    )
  }

  private func makeRetainRequest(
    operation: String,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    reason: String,
    evidenceDigest: ContentDigest
  ) throws -> DesignRevisionRetentionRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let retentionReason = try DesignRevisionRetentionReason(rawValue: reason)
    let requestDigest = try DesignRevisionRetentionDigest.retainingRequest(
      operationID: operationID,
      claimID: claimID,
      revision: revision,
      reason: retentionReason,
      evidenceDigest: evidenceDigest,
      using: SHA256ContentDigester()
    )
    return DesignRevisionRetentionRequest(
      operationID: operationID,
      claimID: claimID,
      revision: revision,
      reason: retentionReason,
      evidenceDigest: evidenceDigest,
      requestDigest: requestDigest
    )
  }

  private func makeReleaseRequest(
    operation: String,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    expectedGeneration: UInt64
  ) throws -> DesignRevisionRetentionReleaseRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let requestDigest = try DesignRevisionRetentionDigest.releasingRequest(
      operationID: operationID,
      claimID: claimID,
      expectedRevision: revision,
      expectedGeneration: expectedGeneration,
      using: SHA256ContentDigester()
    )
    return DesignRevisionRetentionReleaseRequest(
      operationID: operationID,
      claimID: claimID,
      expectedRevision: revision,
      expectedGeneration: expectedGeneration,
      requestDigest: requestDigest
    )
  }

  private func appliedReceipt(
    _ submission: DesignRevisionRetentionSubmission
  ) throws -> DesignRevisionRetentionReceipt {
    guard case .applied(let receipt) = submission else {
      throw RetentionTestError.expectedApplied
    }
    return receipt
  }

  private func rejectedReason(
    _ submission: DesignRevisionRetentionSubmission
  ) throws -> DesignRevisionRetentionRejection.Reason {
    guard case .rejected(let rejection) = submission else {
      throw RetentionTestError.expectedRejected
    }
    return rejection.reason
  }

  private func digest(repeating character: Character) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: character, count: 64)
    )
  }

  private func copyImage(
    _ source: DesignDatabaseImage,
    retentionClaims: [DesignRevisionRetentionID: DesignRevisionRetentionClaim],
    operationRecords: [
      DesignDatabaseOperationReference: DesignDatabaseOperationRecord
    ]
  ) -> DesignDatabaseImage {
    DesignDatabaseImage(
      databaseID: source.databaseID,
      schemas: source.schemas,
      capabilities: source.capabilities,
      revisions: source.revisions,
      references: source.references,
      retentionClaims: retentionClaims,
      operationRecords: operationRecords,
      persistenceGeneration: source.persistenceGeneration,
      reachabilityGeneration: source.reachabilityGeneration,
      nextEntityValue: source.nextEntityValue
    )
  }

  private func expectCorruption(
    _ body: () throws -> Void
  ) {
    do {
      try body()
      Issue.record("Malformed database image was accepted.")
    } catch let error as DesignDatabaseError {
      guard case .corruption = error else {
        Issue.record("Expected corruption, received \(error).")
        return
      }
    } catch {
      Issue.record("Expected DesignDatabaseError.corruption, received \(error).")
    }
  }

  private struct DatabaseFixture {
    let database: any DesignDatabaseReference
    let authority: NativeDesignDatabaseAuthorizationAuthority
    let scopeID: DesignAuthorizationSubjectScopeID
  }

  private enum RetentionTestError: Error {
    case expectedApplied
    case expectedRejected
    case expectedUnknown
  }
}

private actor ReconciliationPersistence: DesignDatabasePersisting {
  private var image: DesignDatabaseImage?
  private var shouldFailAfterCommit = false
  private var shouldFailBeforeCommit = false
  private var shouldHideNextLoad = false
  private var shouldSuspendNextLoad = false
  private var shouldOverrideNextLoad = false
  private var nextLoadOverride: DesignDatabaseImage?
  private var isLoadSuspended = false
  private var loadStartedWaiters: [CheckedContinuation<Void, Never>] = []
  private var loadReleaseContinuation: CheckedContinuation<Void, Never>?
  private var isClosed = false

  func failNextPersistAfterCommit() {
    shouldFailAfterCommit = true
  }

  func failNextPersistBeforeCommitAndHideReconciliation() {
    shouldFailBeforeCommit = true
    shouldHideNextLoad = true
  }

  func failAfterCommitAndSuspendNextReconciliationLoad() {
    shouldFailAfterCommit = true
    shouldSuspendNextLoad = true
  }

  func failBeforeCommitAndReturnOnNextLoad(_ image: DesignDatabaseImage) {
    shouldFailBeforeCommit = true
    shouldOverrideNextLoad = true
    nextLoadOverride = image
  }

  func waitUntilReconciliationLoadIsSuspended() async {
    if isLoadSuspended {
      return
    }
    await withCheckedContinuation { continuation in
      loadStartedWaiters.append(continuation)
    }
  }

  func resumeReconciliationLoad() {
    let continuation = loadReleaseContinuation
    loadReleaseContinuation = nil
    continuation?.resume()
  }

  func snapshotImage() -> DesignDatabaseImage? {
    image
  }

  func load() async throws(DesignDatabaseError) -> DesignDatabaseImage? {
    guard !isClosed else { throw .closed }
    if shouldHideNextLoad {
      shouldHideNextLoad = false
      throw .persistence("Simulated unavailable reconciliation read.")
    }
    if shouldOverrideNextLoad {
      shouldOverrideNextLoad = false
      let result = nextLoadOverride
      nextLoadOverride = nil
      return result
    }
    let result = image
    if shouldSuspendNextLoad {
      shouldSuspendNextLoad = false
      isLoadSuspended = true
      let waiters = loadStartedWaiters
      loadStartedWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      await withCheckedContinuation { continuation in
        loadReleaseContinuation = continuation
      }
      isLoadSuspended = false
    }
    return result
  }

  func persist(
    _ image: DesignDatabaseImage,
    publishing revision: DesignRevisionReference?
  ) throws(DesignDatabaseError) {
    guard !isClosed else { throw .closed }
    if shouldFailBeforeCommit {
      shouldFailBeforeCommit = false
      throw .persistence("Simulated pre-commit persistence failure.")
    }
    self.image = image
    if shouldFailAfterCommit {
      shouldFailAfterCommit = false
      throw .persistence("Simulated lost persistence response.")
    }
  }

  func close() throws(DesignDatabaseError) {
    isClosed = true
  }
}
