import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import DesignDatabaseCore
import Foundation

public actor NativeDesignDatabase: DesignDatabaseReference {
  public nonisolated let databaseID: DesignDatabaseID
  public nonisolated let capabilities: DesignCapabilitySet
  public nonisolated let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public nonisolated let authorizationGrants: DesignDatabaseAuthorizationGrantSet

  private let schemas: [DesignFacetID: DesignFacetSchema]
  private let validators: [DesignFacetID: any DesignFacetValidating]
  private let authorizer: any DesignDatabaseAuthorizing
  private let persistence: (any DesignDatabasePersisting)?
  private let digester: any ContentDigesting
  private let identifierGenerator: RandomDesignIdentifierGenerator
  private var revisions: [DesignRevisionID: DesignStoredRevision]
  private var references: [DesignReferenceName: DesignRevisionReference]
  private var retentionClaims: [
    DesignRevisionRetentionID: DesignRevisionRetentionClaim
  ]
  private var operationRecords: [
    DesignDatabaseOperationReference: DesignDatabaseOperationRecord
  ]
  private var persistenceGeneration: UInt64
  private var reachabilityGeneration: UInt64
  private var nextEntityValue: UInt64
  private var snapshotCache: [DesignRevisionID: DesignReferenceReadSnapshot]
  private var isClosed: Bool
  private var publicationState: NativeDesignDatabasePublicationState

  public init(
    request: DesignReferenceDatabaseCreateRequest,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    authorizationGrants: DesignDatabaseAuthorizationGrantSet,
    authorizer: any DesignDatabaseAuthorizing,
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init()
  ) throws(DesignDatabaseError) {
    let databaseID: DesignDatabaseID
    if let requestedDatabaseID = request.databaseID {
      databaseID = requestedDatabaseID
    } else {
      databaseID = try identifierGenerator.databaseID()
    }
    let schemas = try Self.schemaMap(request.schemas)
    let validators = try Self.validatorMap(request.validators, schemas: schemas)
    let revisionID = identifierGenerator.revisionID()
    let revision = DesignRevisionReference(databaseID: databaseID, revisionID: revisionID)
    let stateDigest = try CanonicalDesignEncoder.stateDigest(entities: [:], using: digester)
    let changeDigest = try CanonicalDesignEncoder.changeDigest(changes: [], using: digester)
    let changeSet = DesignChangeSet(
      baseRevision: revision,
      targetRevision: revision,
      changes: [],
      digest: changeDigest
    )
    let manifest = DesignReferenceRevisionManifest(
      revision: revision,
      parents: [],
      stateDigest: stateDigest,
      schemaDigests: Dictionary(
        uniqueKeysWithValues: schemas.values.map {
          ($0.descriptor.schemaID, $0.descriptor.canonicalDigest)
        }
      ),
      changeSetDigest: changeDigest,
      provenance: nil,
      createdAt: try Self.currentTimestamp()
    )
    self.databaseID = databaseID
    self.capabilities = request.capabilities
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.authorizationGrants = authorizationGrants
    self.schemas = schemas
    self.validators = validators
    self.authorizer = authorizer
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.revisions = [
      revisionID: DesignStoredRevision(manifest: manifest, entities: [:], changeSet: changeSet)
    ]
    self.references = [.main: revision]
    self.retentionClaims = [:]
    self.operationRecords = [:]
    self.persistenceGeneration = 1
    self.reachabilityGeneration = 1
    self.nextEntityValue = 0
    self.snapshotCache = [:]
    self.isClosed = false
    self.publicationState = .idle
  }

  public init(
    image: DesignDatabaseImage,
    validators: [any DesignFacetValidating],
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    authorizationGrants: DesignDatabaseAuthorizationGrantSet,
    authorizer: any DesignDatabaseAuthorizing,
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init()
  ) throws(DesignDatabaseError) {
    let schemas = try Self.schemaMap(image.schemas)
    self.databaseID = image.databaseID
    self.capabilities = image.capabilities
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.authorizationGrants = authorizationGrants
    self.schemas = schemas
    self.validators = try Self.validatorMap(validators, schemas: schemas)
    self.authorizer = authorizer
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.revisions = image.revisions
    self.references = image.references
    self.retentionClaims = image.retentionClaims
    self.operationRecords = image.operationRecords
    self.persistenceGeneration = image.persistenceGeneration
    self.reachabilityGeneration = image.reachabilityGeneration
    self.nextEntityValue = image.nextEntityValue
    self.snapshotCache = [:]
    self.isClosed = false
    self.publicationState = .idle
    try Self.validateImage(image, schemas: schemas, digester: digester)
  }

  public func persistInitialState() async throws(DesignDatabaseError) {
    try requireOpen()
    guard persistence != nil else { return }
    try await persist(
      image(),
      publishing: references[.main],
      missingImageMeansUncommitted: true
    )
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
    try await requireAuthorization(.read)
    try requireOpen()
    switch selector {
    case .exact(let revision):
      try validateDatabase(revision)
      guard revisions[revision.revisionID] != nil else { throw .revisionNotFound(revision) }
      return revision
    case .named(let name):
      guard let revision = references[name] else {
        throw .invalidQuery("Named reference \(name.rawValue) does not exist.")
      }
      return revision
    }
  }

  public func snapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceReadSnapshot {
    try await requireAuthorization(.read)
    try requireOpen()
    try validateDatabase(revision)
    if let cached = snapshotCache[revision.revisionID] { return cached }
    guard let stored = revisions[revision.revisionID] else { throw .revisionNotFound(revision) }
    var changesByBase: [DesignRevisionReference: DesignChangeSet] = [:]
    for ancestorID in try ancestorRevisionIDs(of: revision.revisionID) {
      guard let candidate = revisions[ancestorID] else {
        throw .corruption("Revision ancestry contains an unavailable revision.")
      }
      let base = candidate.manifest.revision
      changesByBase[base] = try changeSet(
        from: candidate.entities,
        base: base,
        to: stored.entities,
        target: revision
      )
    }
    let snapshot = DesignReferenceReadSnapshot(
      revision: revision,
      stateDigest: stored.manifest.stateDigest,
      facetSchemas: schemas,
      entities: stored.entities,
      changesByBase: changesByBase
    )
    snapshotCache[revision.revisionID] = snapshot
    return snapshot
  }

  public func manifest(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceRevisionManifest {
    try await requireAuthorization(.read)
    try requireOpen()
    try validateDatabase(revision)
    guard let stored = revisions[revision.revisionID] else {
      throw .revisionNotFound(revision)
    }
    return stored.manifest
  }

  public func withTransaction<Result: Sendable>(
    from base: DesignRevisionReference,
    options: DesignTransactionOptions,
    _ body: @Sendable (inout DesignTransaction) throws(DesignDatabaseError) -> Result
  ) async throws(DesignDatabaseError) -> DesignTransactionResult<Result> {
    try await requireAuthorization(.proposeCandidate)
    try requireOpen()
    try requirePublicationIdle()
    try validateDatabase(base)
    guard let baseStored = revisions[base.revisionID] else { throw .revisionNotFound(base) }
    if Task.isCancelled { throw .cancelled }

    var transaction = DesignTransaction(
      baseRevision: base,
      schemas: schemas,
      entities: baseStored.entities,
      nextEntityValue: nextEntityValue
    )
    let value = try body(&transaction)
    let state = try transaction.finalized()
    let changedEntityCount = Set(state.changes.map(Self.entityID)).count
    guard UInt64(changedEntityCount) <= options.maximumChangedEntities else {
      throw .resourceExhausted(
        limit: options.maximumChangedEntities,
        requested: UInt64(changedEntityCount)
      )
    }

    var diagnostics: [DesignDiagnostic] = []
    for validator in validators.values {
      diagnostics += try validator.validate(
        proposedEntities: state.entities,
        baseEntities: state.baseEntities,
        changes: state.changes
      )
    }
    if diagnostics.contains(where: { $0.severity >= .error }) {
      throw .validationFailed(diagnostics)
    }

    let candidateID = uniqueRevisionID()
    let candidate = DesignRevisionReference(databaseID: databaseID, revisionID: candidateID)
    let stateDigest = try CanonicalDesignEncoder.stateDigest(
      entities: state.entities,
      using: digester
    )
    let changeSet = try self.changeSet(
      from: baseStored.entities,
      base: base,
      to: state.entities,
      target: candidate
    )
    let provenance = try revisionProvenance(
      options.provenance,
      base: base,
      target: candidate
    )
    let manifest = DesignReferenceRevisionManifest(
      revision: candidate,
      parents: [base],
      stateDigest: stateDigest,
      schemaDigests: Dictionary(
        uniqueKeysWithValues: schemas.values.map {
          ($0.descriptor.schemaID, $0.descriptor.canonicalDigest)
        }
      ),
      changeSetDigest: changeSet.digest,
      provenance: provenance,
      createdAt: try Self.currentTimestamp()
    )
    let stored = DesignStoredRevision(
      manifest: manifest,
      entities: state.entities,
      changeSet: changeSet
    )
    var proposedRevisions = revisions
    proposedRevisions[candidateID] = stored
    let proposedPersistenceGeneration = try incrementedPersistenceGeneration()
    let proposedReachabilityGeneration = try incrementedReachabilityGeneration()
    let proposedImage = image(
      revisions: proposedRevisions,
      references: references,
      persistenceGeneration: proposedPersistenceGeneration,
      reachabilityGeneration: proposedReachabilityGeneration,
      nextEntityValue: state.nextEntityValue
    )
    try await persist(proposedImage, publishing: candidate)
    revisions = proposedRevisions
    persistenceGeneration = proposedPersistenceGeneration
    reachabilityGeneration = proposedReachabilityGeneration
    nextEntityValue = state.nextEntityValue

    return DesignTransactionResult(
      value: value,
      baseRevision: base,
      candidateRevision: candidate,
      stateDigest: stateDigest,
      changes: changeSet,
      diagnostics: diagnostics
    )
  }

  public func compareAndSetReference(
    _ name: DesignReferenceName,
    expected: DesignRevisionReference?,
    desired: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdate {
    try await requireAuthorization(.promoteReference)
    try requireOpen()
    try requirePublicationIdle()
    try validateDatabase(desired)
    guard revisions[desired.revisionID] != nil else { throw .revisionNotFound(desired) }
    if let expected { try validateDatabase(expected) }
    let previous = references[name]
    guard previous == expected else {
      throw .transactionConflict(expected: expected, actual: previous)
    }
    if previous == desired {
      return DesignReferenceUpdate(name: name, previous: previous, current: desired)
    }
    var proposedReferences = references
    proposedReferences[name] = desired
    let proposedPersistenceGeneration = try incrementedPersistenceGeneration()
    let proposedReachabilityGeneration = try incrementedReachabilityGeneration()
    let proposedImage = image(
      revisions: revisions,
      references: proposedReferences,
      persistenceGeneration: proposedPersistenceGeneration,
      reachabilityGeneration: proposedReachabilityGeneration
    )
    try await persist(proposedImage, publishing: nil)
    references = proposedReferences
    persistenceGeneration = proposedPersistenceGeneration
    reachabilityGeneration = proposedReachabilityGeneration
    return DesignReferenceUpdate(name: name, previous: previous, current: desired)
  }

  public func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try await requireAuthorization(.retain)
    try requireOpen()
    try validateDatabase(request.revision)
    let expectedRequestDigest = try DesignRevisionRetentionDigest.retainingRequest(
      operationID: request.operationID,
      claimID: request.claimID,
      revision: request.revision,
      reason: request.reason,
      evidenceDigest: request.evidenceDigest,
      using: digester
    )
    guard request.requestDigest == expectedRequestDigest else {
      throw .contentDigest("Retention request digest does not match its canonical payload.")
    }

    let operation = operationReference(for: request.operationID)
    if let existing = operationRecords[operation] {
      return try retentionSubmission(
        for: existing,
        requestedDigest: request.requestDigest
      )
    }
    if let reconciled = try await reconcilePendingRetentionIfNeeded(
      operation: operation,
      requestDigest: request.requestDigest
    ) {
      return reconciled
    }
    try requirePublicationIdle()

    guard revisions[request.revision.revisionID] != nil else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .revisionNotFound
      )
    }

    if let existingClaim = retentionClaims[request.claimID] {
      let reason: DesignRevisionRetentionRejection.Reason
      if existingClaim.ownerSubjectScopeID != authorizationSubjectScopeID {
        reason = .claimUnavailable
      } else {
        switch existingClaim.state {
        case .active:
          reason = .claimAlreadyActive
        case .released:
          reason = .claimPermanentlyReleased
        }
      }
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: reason
      )
    }

    let proposedReachabilityGeneration = try incrementedReachabilityGeneration()
    let claim = DesignRevisionRetentionClaim(
      claimID: request.claimID,
      revision: request.revision,
      ownerSubjectScopeID: authorizationSubjectScopeID,
      reason: request.reason,
      evidenceDigest: request.evidenceDigest,
      generation: 1,
      state: .active
    )
    let receipt = try retentionReceipt(
      operation: operation,
      requestDigest: request.requestDigest,
      claim: claim,
      reachabilityGeneration: proposedReachabilityGeneration
    )
    let record = DesignDatabaseOperationRecord(
      operation: operation,
      requestDigest: request.requestDigest,
      outcome: .retentionApplied(receipt)
    )
    var proposedClaims = retentionClaims
    proposedClaims[request.claimID] = claim
    var proposedRecords = operationRecords
    proposedRecords[operation] = record
    return try await persistRetentionOperation(
      record,
      proposedClaims: proposedClaims,
      proposedRecords: proposedRecords,
      proposedReachabilityGeneration: proposedReachabilityGeneration
    )
  }

  public func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try await requireAuthorization(.retain)
    try requireOpen()
    try validateDatabase(request.expectedRevision)
    let expectedRequestDigest = try DesignRevisionRetentionDigest.releasingRequest(
      operationID: request.operationID,
      claimID: request.claimID,
      expectedRevision: request.expectedRevision,
      expectedGeneration: request.expectedGeneration,
      using: digester
    )
    guard request.requestDigest == expectedRequestDigest else {
      throw .contentDigest(
        "Retention release request digest does not match its canonical payload."
      )
    }

    let operation = operationReference(for: request.operationID)
    if let existing = operationRecords[operation] {
      return try retentionSubmission(
        for: existing,
        requestedDigest: request.requestDigest
      )
    }
    if let reconciled = try await reconcilePendingRetentionIfNeeded(
      operation: operation,
      requestDigest: request.requestDigest
    ) {
      return reconciled
    }
    try requirePublicationIdle()

    guard let existingClaim = retentionClaims[request.claimID] else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .claimUnavailable
      )
    }
    guard existingClaim.ownerSubjectScopeID == authorizationSubjectScopeID else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .claimUnavailable
      )
    }
    guard existingClaim.state == .active else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .claimPermanentlyReleased
      )
    }
    guard existingClaim.revision == request.expectedRevision else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .revisionMismatch
      )
    }
    guard existingClaim.generation == request.expectedGeneration else {
      return try await persistRetentionRejection(
        operation: operation,
        requestDigest: request.requestDigest,
        reason: .generationMismatch(actual: existingClaim.generation)
      )
    }
    guard existingClaim.generation < UInt64.max else {
      throw .generationExhausted(kind: "Design revision retention claim")
    }

    let proposedReachabilityGeneration = try incrementedReachabilityGeneration()
    let releasedClaim = DesignRevisionRetentionClaim(
      claimID: existingClaim.claimID,
      revision: existingClaim.revision,
      ownerSubjectScopeID: existingClaim.ownerSubjectScopeID,
      reason: existingClaim.reason,
      evidenceDigest: existingClaim.evidenceDigest,
      generation: existingClaim.generation + 1,
      state: .released
    )
    let receipt = try retentionReceipt(
      operation: operation,
      requestDigest: request.requestDigest,
      claim: releasedClaim,
      reachabilityGeneration: proposedReachabilityGeneration
    )
    let record = DesignDatabaseOperationRecord(
      operation: operation,
      requestDigest: request.requestDigest,
      outcome: .retentionApplied(receipt)
    )
    var proposedClaims = retentionClaims
    proposedClaims[request.claimID] = releasedClaim
    var proposedRecords = operationRecords
    proposedRecords[operation] = record
    return try await persistRetentionOperation(
      record,
      proposedClaims: proposedClaims,
      proposedRecords: proposedRecords,
      proposedReachabilityGeneration: proposedReachabilityGeneration
    )
  }

  public func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionStatus {
    try requireOpen()
    guard operation.databaseID == databaseID else {
      throw .crossDatabaseReference(
        expected: databaseID,
        actual: operation.databaseID
      )
    }
    try await requireOutcomeInspectionAuthorization(for: operation)
    try requireOpen()

    if let record = operationRecords[operation] {
      return try retentionStatus(
        for: record,
        requestedDigest: requestDigest
      )
    }
    switch publicationState {
    case .retentionInProgress(let pending):
      guard pending.record.operation == operation else {
        return .notRecorded
      }
      guard pending.record.requestDigest == requestDigest else {
        return .rejected(
          try retentionConflictRejection(
            operation: operation,
            requestDigest: requestDigest
          )
        )
      }
      return .inProgress
    case .unresolvedRetention(let pending):
      guard pending.record.operation == operation else {
        return .notRecorded
      }
      guard pending.record.requestDigest == requestDigest else {
        return .rejected(
          try retentionConflictRejection(
            operation: operation,
            requestDigest: requestDigest
          )
        )
      }
      switch try await reconcilePendingRetention(pending) {
      case .committed(let submission):
        return submission.status
      case .notCommitted:
        return .notRecorded
      case .outcomeUnknown(let unknown):
        return .outcomeUnknown(unknown)
      }
    case .idle, .genericInProgress, .unresolvedGeneric:
      return .notRecorded
    }
  }

  public func close() async throws(DesignDatabaseError) {
    if isClosed { return }
    switch publicationState {
    case .genericInProgress, .retentionInProgress(_):
      throw .persistence("Another publication is in progress.")
    case .idle:
      if persistence != nil {
        try await persist(image(), publishing: nil)
      }
    case .unresolvedGeneric, .unresolvedRetention:
      break
    }
    if let persistence {
      publicationState = .genericInProgress
      do {
        try await persistence.close()
      } catch {
        isClosed = true
        publicationState = .idle
        throw error
      }
    }
    isClosed = true
    publicationState = .idle
  }

  private func persist(
    _ proposedImage: DesignDatabaseImage,
    publishing revision: DesignRevisionReference?,
    missingImageMeansUncommitted: Bool = false
  ) async throws(DesignDatabaseError) {
    guard let persistence else { return }
    try requirePublicationIdle()
    let currentImage = image()
    publicationState = .genericInProgress
    do {
      try await persistence.persist(proposedImage, publishing: revision)
      publicationState = .idle
      return
    } catch let persistenceError {
      let loadedImage: DesignDatabaseImage?
      do {
        loadedImage = try await persistence.load()
      } catch let reconciliationError {
        publicationState = .unresolvedGeneric
        switch reconciliationError {
        case .corruption, .closed:
          throw reconciliationError
        default:
          throw .persistence(
            "Publication outcome is unknown and requires close/reopen reconciliation: "
              + reconciliationError.localizedDescription
          )
        }
      }

      guard let loadedImage else {
        if missingImageMeansUncommitted {
          publicationState = .idle
          throw persistenceError
        }
        publicationState = .unresolvedGeneric
        throw .corruption("The persistent database image disappeared during publication.")
      }

      let reconciliation: NativeDesignDatabaseImageReconciliation
      do {
        reconciliation = try reconcile(
          loadedImage,
          currentImage: currentImage,
          proposedImage: proposedImage
        )
      } catch {
        publicationState = .unresolvedGeneric
        throw error
      }
      publicationState = .idle
      switch reconciliation {
      case .committed:
        return
      case .notCommitted:
        throw persistenceError
      }
    }
  }

  private func image(
    revisions: [DesignRevisionID: DesignStoredRevision]? = nil,
    references: [DesignReferenceName: DesignRevisionReference]? = nil,
    retentionClaims: [
      DesignRevisionRetentionID: DesignRevisionRetentionClaim
    ]? = nil,
    operationRecords: [
      DesignDatabaseOperationReference: DesignDatabaseOperationRecord
    ]? = nil,
    persistenceGeneration: UInt64? = nil,
    reachabilityGeneration: UInt64? = nil,
    nextEntityValue: UInt64? = nil
  ) -> DesignDatabaseImage {
    DesignDatabaseImage(
      databaseID: databaseID,
      schemas: schemas.values.sorted { $0.facetID.rawValue < $1.facetID.rawValue },
      capabilities: capabilities,
      revisions: revisions ?? self.revisions,
      references: references ?? self.references,
      retentionClaims: retentionClaims ?? self.retentionClaims,
      operationRecords: operationRecords ?? self.operationRecords,
      persistenceGeneration: persistenceGeneration ?? self.persistenceGeneration,
      reachabilityGeneration: reachabilityGeneration ?? self.reachabilityGeneration,
      nextEntityValue: nextEntityValue ?? self.nextEntityValue
    )
  }

  private func uniqueRevisionID() -> DesignRevisionID {
    var candidate = identifierGenerator.revisionID()
    while revisions[candidate] != nil {
      candidate = identifierGenerator.revisionID()
    }
    return candidate
  }

  private func validateDatabase(_ revision: DesignRevisionReference) throws(DesignDatabaseError) {
    guard revision.databaseID == databaseID else {
      throw .crossDatabaseReference(expected: databaseID, actual: revision.databaseID)
    }
  }

  private func requireOpen() throws(DesignDatabaseError) {
    if isClosed { throw .closed }
  }

  private func requirePublicationIdle() throws(DesignDatabaseError) {
    switch publicationState {
    case .idle:
      return
    case .genericInProgress, .retentionInProgress(_):
      throw .persistence("Another publication is in progress.")
    case .unresolvedGeneric:
      throw .persistence(
        "A publication outcome is unresolved; close and reopen before mutating."
      )
    case .unresolvedRetention(let pending):
      throw .persistence(
        "Retention operation \(pending.record.operation.operationID.rawValue) "
          + "must be reconciled before mutating."
      )
    }
  }

  private func requireAuthorization(
    _ grant: DesignDatabaseAuthorizationGrant
  ) async throws(DesignDatabaseError) {
    try await authorizer.authorize(
      grant,
      for: authorizationSubjectScopeID
    )
  }

  private func requireOutcomeInspectionAuthorization(
    for operation: DesignDatabaseOperationReference
  ) async throws(DesignDatabaseError) {
    guard operation.authorizationSubjectScopeID == authorizationSubjectScopeID else {
      try await requireAuthorization(.administer)
      return
    }
    do {
      try await requireAuthorization(.inspectOwnOperationOutcome)
    } catch let error {
      guard case .unauthorized = error else {
        throw error
      }
      try await requireAuthorization(.administer)
    }
  }

  private func operationReference(
    for operationID: DesignDatabaseOperationID
  ) -> DesignDatabaseOperationReference {
    DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      operationID: operationID
    )
  }

  private func incrementedPersistenceGeneration() throws(
    DesignDatabaseError
  ) -> UInt64 {
    guard persistenceGeneration < UInt64.max else {
      throw .generationExhausted(kind: "Database persistence")
    }
    return persistenceGeneration + 1
  }

  private func incrementedReachabilityGeneration() throws(
    DesignDatabaseError
  ) -> UInt64 {
    guard reachabilityGeneration < UInt64.max else {
      throw .generationExhausted(kind: "Database reachability")
    }
    return reachabilityGeneration + 1
  }

  private func reconcile(
    _ loadedImage: DesignDatabaseImage,
    currentImage: DesignDatabaseImage,
    proposedImage: DesignDatabaseImage
  ) throws(DesignDatabaseError) -> NativeDesignDatabaseImageReconciliation {
    guard loadedImage.databaseID == databaseID else {
      throw .corruption(
        "Persistence returned database \(loadedImage.databaseID), expected \(databaseID)."
      )
    }
    try Self.validateImage(loadedImage, schemas: schemas, digester: digester)

    if loadedImage.persistenceGeneration == proposedImage.persistenceGeneration {
      guard loadedImage == proposedImage else {
        throw .corruption(
          "Persisted image diverged at proposed generation "
            + "\(proposedImage.persistenceGeneration)."
        )
      }
      return .committed
    }
    if loadedImage.persistenceGeneration == currentImage.persistenceGeneration {
      guard loadedImage == currentImage else {
        throw .corruption(
          "Persisted image diverged at current generation "
            + "\(currentImage.persistenceGeneration)."
        )
      }
      return .notCommitted
    }
    throw .corruption(
      "Persisted image generation \(loadedImage.persistenceGeneration) is neither "
        + "current \(currentImage.persistenceGeneration) nor proposed "
        + "\(proposedImage.persistenceGeneration)."
    )
  }

  private func retentionReceipt(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    claim: DesignRevisionRetentionClaim,
    reachabilityGeneration: UInt64
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionReceipt {
    let outcomeDigest = try DesignRevisionRetentionDigest.appliedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      claimID: claim.claimID,
      revision: claim.revision,
      generation: claim.generation,
      reachabilityGeneration: reachabilityGeneration,
      state: claim.state,
      using: digester
    )
    return DesignRevisionRetentionReceipt(
      operation: operation,
      claimID: claim.claimID,
      revision: claim.revision,
      generation: claim.generation,
      reachabilityGeneration: reachabilityGeneration,
      state: claim.state,
      outcomeDigest: outcomeDigest
    )
  }

  private func retentionSubmission(
    for record: DesignDatabaseOperationRecord,
    requestedDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    guard record.requestDigest == requestedDigest else {
      return .rejected(try retentionConflictRejection(
        operation: record.operation,
        requestDigest: requestedDigest
      ))
    }
    return record.retentionSubmission
  }

  private func retentionConflictRejection(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionRejection {
    let reason = DesignRevisionRetentionRejection.Reason.operationRequestConflict
    return DesignRevisionRetentionRejection(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      outcomeDigest: try DesignRevisionRetentionDigest.rejectedOutcome(
        operation: operation,
        requestDigest: requestDigest,
        reason: reason,
        using: digester
      )
    )
  }

  private func retentionStatus(
    for record: DesignDatabaseOperationRecord,
    requestedDigest: ContentDigest
  ) throws(DesignDatabaseError) -> DesignRevisionRetentionStatus {
    guard record.requestDigest == requestedDigest else {
      return .rejected(try retentionConflictRejection(
        operation: record.operation,
        requestDigest: requestedDigest
      ))
    }
    return record.retentionStatus
  }

  private func reconcilePendingRetentionIfNeeded(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission? {
    switch publicationState {
    case .unresolvedRetention(let pending):
      guard pending.record.operation == operation else {
        return nil
      }
      guard pending.record.requestDigest == requestDigest else {
        return .rejected(try retentionConflictRejection(
          operation: operation,
          requestDigest: requestDigest
        ))
      }
      switch try await reconcilePendingRetention(pending) {
      case .committed(let submission):
        return submission
      case .notCommitted:
        return nil
      case .outcomeUnknown(let unknown):
        return .outcomeUnknown(unknown)
      }
    case .retentionInProgress(let pending):
      guard pending.record.operation == operation else {
        return nil
      }
      guard pending.record.requestDigest == requestDigest else {
        return .rejected(try retentionConflictRejection(
          operation: operation,
          requestDigest: requestDigest
        ))
      }
      throw .persistence(
        "Retention operation \(operation.operationID.rawValue) is still in progress."
      )
    case .idle, .genericInProgress, .unresolvedGeneric:
      return nil
    }
  }

  private func persistRetentionRejection(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    reason: DesignRevisionRetentionRejection.Reason
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    let outcomeDigest = try DesignRevisionRetentionDigest.rejectedOutcome(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      using: digester
    )
    let rejection = DesignRevisionRetentionRejection(
      operation: operation,
      requestDigest: requestDigest,
      reason: reason,
      outcomeDigest: outcomeDigest
    )
    let record = DesignDatabaseOperationRecord(
      operation: operation,
      requestDigest: requestDigest,
      outcome: .retentionRejected(rejection)
    )
    var proposedRecords = operationRecords
    proposedRecords[operation] = record
    return try await persistRetentionOperation(
      record,
      proposedClaims: retentionClaims,
      proposedRecords: proposedRecords,
      proposedReachabilityGeneration: reachabilityGeneration
    )
  }

  private func persistRetentionOperation(
    _ record: DesignDatabaseOperationRecord,
    proposedClaims: [DesignRevisionRetentionID: DesignRevisionRetentionClaim],
    proposedRecords: [
      DesignDatabaseOperationReference: DesignDatabaseOperationRecord
    ],
    proposedReachabilityGeneration: UInt64
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission {
    try requirePublicationIdle()
    let proposedPersistenceGeneration = try incrementedPersistenceGeneration()
    let currentImage = image()
    let proposedImage = image(
      retentionClaims: proposedClaims,
      operationRecords: proposedRecords,
      persistenceGeneration: proposedPersistenceGeneration,
      reachabilityGeneration: proposedReachabilityGeneration
    )
    let pending = NativePendingRetentionPublication(
      record: record,
      currentImage: currentImage,
      proposedImage: proposedImage
    )
    guard let persistence else {
      adopt(proposedImage)
      return record.retentionSubmission
    }
    publicationState = .retentionInProgress(pending)
    do {
      try await persistence.persist(proposedImage, publishing: nil)
      adopt(proposedImage)
      publicationState = .idle
      return record.retentionSubmission
    } catch let persistenceError {
      switch try await reconcilePendingRetention(pending) {
      case .committed(let submission):
        return submission
      case .notCommitted:
        throw persistenceError
      case .outcomeUnknown(let unknown):
        return .outcomeUnknown(unknown)
      }
    }
  }

  private func reconcilePendingRetention(
    _ pending: NativePendingRetentionPublication
  ) async throws(DesignDatabaseError) -> NativeRetentionReconciliation {
    guard let persistence else {
      publicationState = .unresolvedRetention(pending)
      throw .corruption("Retention reconciliation has no persistence backend.")
    }
    publicationState = .retentionInProgress(pending)
    let loadedImage: DesignDatabaseImage?
    do {
      loadedImage = try await persistence.load()
    } catch let reconciliationError {
      publicationState = .unresolvedRetention(pending)
      switch reconciliationError {
      case .corruption, .closed:
        throw reconciliationError
      default:
        return .outcomeUnknown(
          DesignRevisionRetentionUnknown(
            operation: pending.record.operation,
            requestDigest: pending.record.requestDigest
          )
        )
      }
    }
    guard let loadedImage else {
      publicationState = .unresolvedRetention(pending)
      throw .corruption("The persistent database image disappeared during reconciliation.")
    }

    let reconciliation: NativeDesignDatabaseImageReconciliation
    do {
      reconciliation = try reconcile(
        loadedImage,
        currentImage: pending.currentImage,
        proposedImage: pending.proposedImage
      )
    } catch {
      publicationState = .unresolvedRetention(pending)
      throw error
    }
    switch reconciliation {
    case .committed:
      adopt(loadedImage)
      publicationState = .idle
      return .committed(pending.record.retentionSubmission)
    case .notCommitted:
      publicationState = .idle
      return .notCommitted
    }
  }

  private func adopt(_ image: DesignDatabaseImage) {
    revisions = image.revisions
    references = image.references
    retentionClaims = image.retentionClaims
    operationRecords = image.operationRecords
    persistenceGeneration = image.persistenceGeneration
    reachabilityGeneration = image.reachabilityGeneration
    nextEntityValue = image.nextEntityValue
    snapshotCache = [:]
  }

  private func changeSet(
    from baseEntities: [DesignEntityID: DesignEntityRecord],
    base: DesignRevisionReference,
    to targetEntities: [DesignEntityID: DesignEntityRecord],
    target: DesignRevisionReference
  ) throws(DesignDatabaseError) -> DesignChangeSet {
    try Self.changeSet(
      from: baseEntities,
      base: base,
      to: targetEntities,
      target: target,
      digester: digester
    )
  }

  private static func changeSet(
    from baseEntities: [DesignEntityID: DesignEntityRecord],
    base: DesignRevisionReference,
    to targetEntities: [DesignEntityID: DesignEntityRecord],
    target: DesignRevisionReference,
    digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> DesignChangeSet {
    var changes: [DesignEntityChange] = []
    let allIDs = Set(baseEntities.keys).union(targetEntities.keys)
    for id in allIDs.sorted() {
      switch (baseEntities[id], targetEntities[id]) {
      case (nil, .some): changes.append(.created(id))
      case (.some, nil): changes.append(.deleted(id))
      case (.some(let old), .some(let new)):
        for field in Set(old.fields.keys).union(new.fields.keys).sorted()
          where old.fields[field] != new.fields[field]
        {
          changes.append(.fieldChanged(entity: id, field: field))
        }
        for relation in Set(old.relations.keys).union(new.relations.keys).sorted()
          where old.relations[relation] != new.relations[relation]
        {
          changes.append(.relationChanged(entity: id, relation: relation))
        }
        if old.spatialEntries != new.spatialEntries { changes.append(.spatialChanged(id)) }
      case (nil, nil): break
      }
    }
    let sorted = CanonicalDesignEncoder.sortedChanges(changes)
    return DesignChangeSet(
      baseRevision: base,
      targetRevision: target,
      changes: sorted,
      digest: try CanonicalDesignEncoder.changeDigest(changes: sorted, using: digester)
    )
  }

  private func ancestorRevisionIDs(
    of revisionID: DesignRevisionID
  ) throws(DesignDatabaseError) -> Set<DesignRevisionID> {
    var pending = [revisionID]
    var result = Set<DesignRevisionID>()
    while let current = pending.popLast() {
      guard result.insert(current).inserted else { continue }
      guard let stored = revisions[current] else {
        throw .corruption("Revision ancestry contains an unavailable revision.")
      }
      pending.append(contentsOf: stored.manifest.parents.map(\.revisionID))
    }
    return result
  }

  private func revisionProvenance(
    _ source: ExecutionProvenance?,
    base: DesignRevisionReference,
    target: DesignRevisionReference
  ) throws(DesignDatabaseError) -> ExecutionProvenance? {
    guard let source else { return nil }
    if let input = source.inputDesignRevision, input != base {
      throw .invalidQuery("Transaction provenance input revision does not match its base revision.")
    }
    if let output = source.outputDesignRevision, output != target {
      throw .invalidQuery("Transaction provenance output revision does not match its candidate revision.")
    }
    do {
      return try ExecutionProvenance(
        producer: source.producer,
        supportingTools: source.supportingTools,
        inputs: source.inputs,
        invocation: source.invocation,
        environment: source.environment,
        configurationDigest: source.configurationDigest,
        inputDesignRevision: base,
        outputDesignRevision: target,
        randomSeed: source.randomSeed,
        startedAt: source.startedAt,
        completedAt: source.completedAt
      )
    } catch {
      throw .corruption("Validated execution provenance could not be revision-scoped.")
    }
  }

  private static func currentTimestamp() throws(DesignDatabaseError) -> ExecutionTimestamp {
    do {
      return try ExecutionTimestamp(Date())
    } catch {
      throw .corruption("The system clock produced a non-finite execution timestamp.")
    }
  }

  private static func entityID(_ change: DesignEntityChange) -> DesignEntityID {
    switch change {
    case .created(let id), .deleted(let id), .spatialChanged(let id): return id
    case .fieldChanged(let id, _), .relationChanged(let id, _): return id
    }
  }

  private static func schemaMap(
    _ values: [DesignFacetSchema]
  ) throws(DesignDatabaseError) -> [DesignFacetID: DesignFacetSchema] {
    var result: [DesignFacetID: DesignFacetSchema] = [:]
    var schemaIDs = Set<DesignSchemaID>()
    for value in values {
      guard result.updateValue(value, forKey: value.facetID) == nil else {
        throw .invalidToken(kind: "Duplicate facet", value: value.facetID.rawValue)
      }
      guard schemaIDs.insert(value.descriptor.schemaID).inserted else {
        throw .invalidToken(
          kind: "Duplicate schema identifier",
          value: value.descriptor.schemaID.rawValue
        )
      }
    }
    let requiredSchemas = Set(values.flatMap(\.descriptor.requiredSchemas))
    let report: DesignCompatibilityReport
    do {
      report = try DesignCompatibilityNegotiator.negotiate(
        offeredSchemas: values.map(\.descriptor),
        requiredSchemas: Array(requiredSchemas),
        offeredCapabilities: DesignCapabilitySet([]),
        requiredCapabilities: []
      )
    } catch let error {
      throw .schemaContract(error)
    }
    guard report.isCompatible else { throw .incompatibleSchema(report) }
    return result
  }

  private static func validatorMap(
    _ values: [any DesignFacetValidating],
    schemas: [DesignFacetID: DesignFacetSchema]
  ) throws(DesignDatabaseError) -> [DesignFacetID: any DesignFacetValidating] {
    var result: [DesignFacetID: any DesignFacetValidating] = [:]
    for value in values {
      guard schemas[value.facetID] != nil else { throw .unknownFacet(value.facetID) }
      guard result.updateValue(value, forKey: value.facetID) == nil else {
        throw .invalidToken(kind: "Duplicate facet validator", value: value.facetID.rawValue)
      }
    }
    return result
  }

  private static func validateImage(
    _ image: DesignDatabaseImage,
    schemas: [DesignFacetID: DesignFacetSchema],
    digester: any ContentDigesting
  ) throws(DesignDatabaseError) {
    let expectedSchemaDigests = Dictionary(
      uniqueKeysWithValues: schemas.values.map {
        ($0.descriptor.schemaID, $0.descriptor.canonicalDigest)
      }
    )
    var maximumEntityValue: UInt64 = 0
    var childrenByParent: [DesignRevisionID: Set<DesignRevisionID>] = [:]
    var parentCounts: [DesignRevisionID: Int] = [:]

    for (revisionID, stored) in image.revisions {
      guard stored.manifest.revision.revisionID == revisionID else {
        throw .corruption("Revision dictionary key does not match its manifest.")
      }
      guard stored.manifest.revision.databaseID == image.databaseID else {
        throw .corruption("Revision belongs to a different database.")
      }
      guard stored.manifest.schemaDigests == expectedSchemaDigests else {
        throw .corruption("Revision schema digest inventory does not match the database schema.")
      }
      guard stored.manifest.parents.count <= 1 else {
        throw .corruption("Merge revisions are not supported by this storage backend.")
      }
      let uniqueParents = Set(stored.manifest.parents)
      guard uniqueParents.count == stored.manifest.parents.count else {
        throw .corruption("Revision manifest contains duplicate parents.")
      }
      parentCounts[revisionID] = stored.manifest.parents.count
      for parent in stored.manifest.parents {
        guard parent.databaseID == image.databaseID,
          image.revisions[parent.revisionID] != nil
        else {
          throw .corruption("Revision manifest refers to an unavailable parent.")
        }
        childrenByParent[parent.revisionID, default: []].insert(revisionID)
      }

      let digest = try CanonicalDesignEncoder.stateDigest(entities: stored.entities, using: digester)
      guard digest == stored.manifest.stateDigest else {
        throw .corruption("Revision state digest mismatch for \(stored.manifest.revision.revisionID).")
      }
      guard stored.changeSet.targetRevision == stored.manifest.revision else {
        throw .corruption("Change set target does not match its revision manifest.")
      }
      let expectedBase = stored.manifest.parents.first ?? stored.manifest.revision
      guard stored.changeSet.baseRevision == expectedBase else {
        throw .corruption("Change set base does not match its revision parent.")
      }
      let baseEntities = stored.manifest.parents.first.flatMap {
        image.revisions[$0.revisionID]?.entities
      } ?? [:]
      let expectedChangeSet = try changeSet(
        from: baseEntities,
        base: expectedBase,
        to: stored.entities,
        target: stored.manifest.revision,
        digester: digester
      )
      guard stored.changeSet.changes == expectedChangeSet.changes,
        stored.changeSet.digest == expectedChangeSet.digest,
        stored.manifest.changeSetDigest == expectedChangeSet.digest
      else {
        throw .corruption("Revision change set does not match its entity state.")
      }

      for (entityID, record) in stored.entities {
        guard record.key.entityID == entityID else {
          throw .corruption("Entity dictionary key does not match its record.")
        }
        guard record.key.databaseID == image.databaseID else {
          throw .corruption("Entity belongs to a different database.")
        }
        maximumEntityValue = max(maximumEntityValue, record.key.entityID.rawValue)
        guard let facetSchema = schemas[record.facetID] else {
          throw .corruption("Entity refers to an unavailable facet.")
        }
        guard let entitySchema = facetSchema.entities.first(where: {
          $0.kindID == record.kindID
        }) else {
          throw .corruption("Entity refers to an unavailable kind.")
        }
        for field in record.fields {
          guard let fieldSchema = entitySchema.fields.first(where: { $0.id == field.key }),
            fieldSchema.valueKind.accepts(field.value)
          else {
            throw .corruption("Entity field does not match its schema.")
          }
        }
        for field in entitySchema.fields where field.isRequired && record.fields[field.id] == nil {
          throw .corruption("Entity is missing a required field.")
        }
        for relation in record.relations {
          guard let relationSchema = entitySchema.relations.first(where: {
            $0.id == relation.key
          }) else {
            throw .corruption("Entity relation does not match its schema.")
          }
          for target in relation.value {
            guard let targetRecord = stored.entities[target] else {
              throw .corruption("Entity relation targets an unavailable entity.")
            }
            guard relationSchema.targetFacets.isEmpty
              || relationSchema.targetFacets.contains(targetRecord.facetID)
            else {
              throw .corruption("Entity relation target facet does not match its schema.")
            }
          }
        }
        guard record.spatialEntries.isEmpty || facetSchema.indexes.contains(.spatial) else {
          throw .corruption("Entity has spatial data without a spatial facet index.")
        }
      }
      if let conflict = uniquenessConflict(in: stored.entities, schemas: schemas) {
        throw .corruption(
          "Entities \(conflict.first.entityID) and \(conflict.second.entityID) violate unique constraint \(conflict.constraint.rawValue)."
        )
      }
    }

    var ready = parentCounts.compactMap { $0.value == 0 ? $0.key : nil }
    var visitedCount = 0
    while let current = ready.popLast() {
      visitedCount += 1
      for child in childrenByParent[current] ?? [] {
        guard let count = parentCounts[child] else {
          throw .corruption("Revision graph contains an unknown child.")
        }
        parentCounts[child] = count - 1
        if count == 1 { ready.append(child) }
      }
    }
    guard visitedCount == image.revisions.count else {
      throw .corruption("Revision graph contains a cycle.")
    }
    guard image.nextEntityValue >= maximumEntityValue else {
      throw .corruption("Entity allocator state is behind persisted entity identifiers.")
    }
    guard image.references[.main] != nil else {
      throw .corruption("Database image does not contain the main reference.")
    }
    for revision in image.references.values {
      guard revision.databaseID == image.databaseID, image.revisions[revision.revisionID] != nil else {
        throw .corruption("A named reference targets an unavailable revision.")
      }
    }
    guard image.persistenceGeneration > 0 else {
      throw .corruption("Database persistence generation must be nonzero.")
    }
    guard image.reachabilityGeneration > 0,
      image.persistenceGeneration >= image.reachabilityGeneration
    else {
      throw .corruption(
        "Database reachability generation must be nonzero and cannot exceed persistence."
      )
    }
    for (claimID, claim) in image.retentionClaims {
      guard claim.claimID == claimID else {
        throw .corruption("Retention claim dictionary key does not match its record.")
      }
      guard claim.revision.databaseID == image.databaseID,
        image.revisions[claim.revision.revisionID] != nil
      else {
        throw .corruption("Retention claim targets an unavailable revision.")
      }
      switch claim.state {
      case .active:
        guard claim.generation == 1 else {
          throw .corruption("Active retention claim must have generation 1.")
        }
      case .released:
        guard claim.generation == 2 else {
          throw .corruption("Released retention claim must have generation 2.")
        }
      }
    }
    var appliedReceiptsByClaim: [
      DesignRevisionRetentionID: [DesignRevisionRetentionReceipt]
    ] = [:]
    for (operation, record) in image.operationRecords {
      guard operation == record.operation else {
        throw .corruption("Operation dictionary key does not match its record.")
      }
      guard operation.databaseID == image.databaseID else {
        throw .corruption("Operation record belongs to a different database.")
      }
      switch record.outcome {
      case .retentionApplied(let receipt):
        guard receipt.operation == operation else {
          throw .corruption("Retention receipt operation does not match its record.")
        }
        guard receipt.generation > 0,
          receipt.reachabilityGeneration > 0,
          receipt.reachabilityGeneration <= image.reachabilityGeneration
        else {
          throw .corruption("Retention receipt generation is invalid.")
        }
        guard let claim = image.retentionClaims[receipt.claimID],
          claim.revision == receipt.revision,
          claim.ownerSubjectScopeID == operation.authorizationSubjectScopeID,
          receipt.generation <= claim.generation
        else {
          throw .corruption("Retention receipt does not match a retained claim.")
        }
        switch receipt.state {
        case .active:
          guard receipt.generation == 1 else {
            throw .corruption("Active retention receipt has an invalid generation.")
          }
          let expectedRequestDigest = try DesignRevisionRetentionDigest.retainingRequest(
            operationID: operation.operationID,
            claimID: receipt.claimID,
            revision: receipt.revision,
            reason: claim.reason,
            evidenceDigest: claim.evidenceDigest,
            using: digester
          )
          guard record.requestDigest == expectedRequestDigest else {
            throw .corruption("Retention activation request digest mismatch.")
          }
        case .released:
          guard claim.state == .released,
            claim.generation == 2,
            receipt.generation == 2
          else {
            throw .corruption("Released retention receipt does not match its tombstone.")
          }
          let expectedRequestDigest = try DesignRevisionRetentionDigest.releasingRequest(
            operationID: operation.operationID,
            claimID: receipt.claimID,
            expectedRevision: receipt.revision,
            expectedGeneration: receipt.generation - 1,
            using: digester
          )
          guard record.requestDigest == expectedRequestDigest else {
            throw .corruption("Retention release request digest mismatch.")
          }
        }
        let expectedOutcomeDigest = try DesignRevisionRetentionDigest.appliedOutcome(
          operation: operation,
          requestDigest: record.requestDigest,
          claimID: receipt.claimID,
          revision: receipt.revision,
          generation: receipt.generation,
          reachabilityGeneration: receipt.reachabilityGeneration,
          state: receipt.state,
          using: digester
        )
        guard receipt.outcomeDigest == expectedOutcomeDigest else {
          throw .corruption("Retention receipt outcome digest mismatch.")
        }
        appliedReceiptsByClaim[receipt.claimID, default: []].append(receipt)
      case .retentionRejected(let rejection):
        guard rejection.operation == operation,
          rejection.requestDigest == record.requestDigest
        else {
          throw .corruption("Retention rejection does not match its operation record.")
        }
        let expectedOutcomeDigest = try DesignRevisionRetentionDigest.rejectedOutcome(
          operation: operation,
          requestDigest: record.requestDigest,
          reason: rejection.reason,
          using: digester
        )
        guard rejection.outcomeDigest == expectedOutcomeDigest else {
          throw .corruption("Retention rejection outcome digest mismatch.")
        }
      }
    }
    for (claimID, claim) in image.retentionClaims {
      let receipts = appliedReceiptsByClaim[claimID] ?? []
      let activations = receipts.filter { $0.state == .active }
      let releases = receipts.filter { $0.state == .released }
      guard activations.count == 1 else {
        throw .corruption(
          "Retention claim \(claimID.rawValue) must have exactly one activation outcome."
        )
      }
      switch claim.state {
      case .active:
        guard releases.isEmpty else {
          throw .corruption("Active retention claim has a release outcome.")
        }
      case .released:
        guard releases.count == 1,
          let activation = activations.first,
          let release = releases.first,
          activation.reachabilityGeneration < release.reachabilityGeneration
        else {
          throw .corruption(
            "Released retention claim must have one ordered release outcome."
          )
        }
      }
    }
  }

  private static func uniquenessConflict(
    in entities: [DesignEntityID: DesignEntityRecord],
    schemas: [DesignFacetID: DesignFacetSchema]
  ) -> (
    constraint: DesignUniqueConstraintID,
    first: DesignEntityKey,
    second: DesignEntityKey
  )? {
    for facetSchema in schemas.values.sorted(by: {
      $0.facetID.rawValue < $1.facetID.rawValue
    }) {
      for entitySchema in facetSchema.entities {
        let records = entities.values
          .filter { $0.facetID == facetSchema.facetID && $0.kindID == entitySchema.kindID }
          .sorted { $0.key.entityID < $1.key.entityID }
        for constraint in entitySchema.uniqueConstraints {
          var owners: [[DesignValue]: DesignEntityKey] = [:]
          for record in records {
            let values = constraint.fields.compactMap { record.fields[$0] }
            guard values.count == constraint.fields.count else { continue }
            if let first = owners[values] {
              return (constraint.id, first, record.key)
            }
            owners[values] = record.key
          }
        }
      }
    }
    return nil
  }
}

private enum NativeDesignDatabasePublicationState {
  case idle
  case genericInProgress
  case retentionInProgress(NativePendingRetentionPublication)
  case unresolvedGeneric
  case unresolvedRetention(NativePendingRetentionPublication)
}

private struct NativePendingRetentionPublication {
  let record: DesignDatabaseOperationRecord
  let currentImage: DesignDatabaseImage
  let proposedImage: DesignDatabaseImage
}

private enum NativeDesignDatabaseImageReconciliation {
  case committed
  case notCommitted
}

private enum NativeRetentionReconciliation {
  case committed(DesignRevisionRetentionSubmission)
  case notCommitted
  case outcomeUnknown(DesignRevisionRetentionUnknown)
}

private extension DesignRevisionRetentionSubmission {
  var status: DesignRevisionRetentionStatus {
    switch self {
    case .applied(let receipt):
      return .applied(receipt)
    case .rejected(let rejection):
      return .rejected(rejection)
    case .outcomeUnknown(let unknown):
      return .outcomeUnknown(unknown)
    }
  }
}
