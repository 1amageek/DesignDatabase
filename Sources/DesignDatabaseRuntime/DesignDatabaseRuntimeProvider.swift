import CircuiteFoundation
import DesignDatabaseCore

public actor DesignDatabaseRuntimeProvider: DesignDatabaseProviding {
  private let registration: DesignDatabaseRuntimeRegistrationBundle
  private let containerProvider: any DesignDatabaseRuntimeContainerProviding
  private let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  private let creationRequestedAuthorization: DesignDatabaseAuthorizationGrantSet
  private let authorizer: any DesignDatabaseAuthorizing
  private var handles: [DesignDatabaseRuntimeHandle] = []
  private var isClosed = false

  public init(
    registration: DesignDatabaseRuntimeRegistrationBundle,
    containerProvider: any DesignDatabaseRuntimeContainerProviding,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    creationRequestedAuthorization: DesignDatabaseAuthorizationGrantSet,
    authorizer: any DesignDatabaseAuthorizing
  ) {
    self.registration = registration
    self.containerProvider = containerProvider
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.creationRequestedAuthorization = creationRequestedAuthorization
    self.authorizer = authorizer
  }

  public func create(
    _ request: DesignDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle {
    try requireOpen()
    let grants = try await authorizer.authorizeRequestedGrants(
      creationRequestedAuthorization,
      for: authorizationSubjectScopeID
    )
    try requireOpen()
    return try await DesignDatabaseRuntimeStorageSecurity.withAuthorizedDatabaseAccess {
      () async throws(DesignDatabaseError) -> any DesignDatabaseHandle in
      try await self.createWithAuthorizedStorage(request, grants: grants)
    }
  }

  private func createWithAuthorizedStorage(
    _ request: DesignDatabaseCreateRequest,
    grants: DesignDatabaseAuthorizationGrantSet
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle {
    guard request.initialSchemaBundle == registration.designSchemaBundle else {
      throw .runtimeRegistrationMismatch
    }

    let genesisRequest: DesignDatabaseRuntimeGenesisRequest
    do {
      genesisRequest = try DesignDatabaseRuntimeGenesisRequest(
        locator: request.locator,
        databaseID: request.databaseID,
        genesisRevisionID: request.genesisRevisionID,
        authorizationSubjectScopeID: authorizationSubjectScopeID,
        operationID: request.operationID,
        declaredFeatureCapabilities: request.declaredFeatureCapabilities,
        initialSchemaBundle: request.initialSchemaBundle,
        registrationDigest: registration.registrationDigest
      )
    } catch {
      throw .contentDigest(String(describing: error))
    }
    guard genesisRequest.requestDigest == request.requestDigest else {
      throw .contentDigest("The creation request digest does not match its canonical payload.")
    }

    let attachment = try await openAttachment(
      locator: request.locator,
      expectedDatabaseID: request.databaseID,
      operation: genesisRequest
    )
    do {
      let submission = try await attachment.createGenesis(genesisRequest)
      switch submission {
      case .created:
        break
      case .outcomeUnknown(let unknown):
        _ = await attachment.close()
        throw DesignDatabaseError.outcomeUnknown(
          operation: unknown.operation,
          requestDigest: unknown.requestDigest
        )
      }
      let descriptor = try await attachment.inspectDatabase(
        expectedDatabaseID: request.databaseID,
        requiredFeatureCapabilities: request.declaredFeatureCapabilities
      )
      guard !isClosed else {
        _ = await attachment.close()
        throw DesignDatabaseError.closed
      }
      let handle = DesignDatabaseRuntimeHandle(
        descriptor: descriptor,
        authorizationSubjectScopeID: authorizationSubjectScopeID,
        authorizationGrants: grants,
        authorizer: authorizer,
        attachment: attachment
      )
      handles.append(handle)
      return handle
    } catch let error as DesignDatabaseError {
      _ = await attachment.close()
      throw error
    } catch let error as DesignDatabaseRuntimeError {
      _ = await attachment.close()
      throw Self.map(
        error,
        locator: request.locator,
        expectedDatabaseID: request.databaseID,
        operation: genesisRequest
      )
    } catch {
      _ = await attachment.close()
      throw .persistence(String(describing: error))
    }
  }

  public func open(
    _ request: DesignDatabaseOpenRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle {
    try requireOpen()
    let grants = try await authorizer.authorizeRequestedGrants(
      request.requestedAuthorization,
      for: authorizationSubjectScopeID
    )
    try requireOpen()
    return try await DesignDatabaseRuntimeStorageSecurity.withAuthorizedDatabaseAccess {
      () async throws(DesignDatabaseError) -> any DesignDatabaseHandle in
      try await self.openWithAuthorizedStorage(request, grants: grants)
    }
  }

  private func openWithAuthorizedStorage(
    _ request: DesignDatabaseOpenRequest,
    grants: DesignDatabaseAuthorizationGrantSet
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle {
    let attachment = try await openAttachment(
      locator: request.locator,
      expectedDatabaseID: request.expectedDatabaseID,
      operation: nil
    )
    do {
      let descriptor = try await attachment.inspectDatabase(
        expectedDatabaseID: request.expectedDatabaseID,
        requiredFeatureCapabilities: request.requiredFeatureCapabilities
      )
      guard !isClosed else {
        _ = await attachment.close()
        throw DesignDatabaseError.closed
      }
      let handle = DesignDatabaseRuntimeHandle(
        descriptor: descriptor,
        authorizationSubjectScopeID: authorizationSubjectScopeID,
        authorizationGrants: grants,
        authorizer: authorizer,
        attachment: attachment
      )
      handles.append(handle)
      return handle
    } catch let error as DesignDatabaseError {
      _ = await attachment.close()
      throw error
    } catch let error as DesignDatabaseRuntimeError {
      _ = await attachment.close()
      throw Self.map(
        error,
        locator: request.locator,
        expectedDatabaseID: request.expectedDatabaseID,
        operation: nil
      )
    } catch {
      _ = await attachment.close()
      throw .persistence(String(describing: error))
    }
  }

  public func close() async -> DesignDatabaseTermination {
    guard !isClosed else { return .alreadyClosed }
    isClosed = true
    for handle in handles {
      _ = await handle.close()
    }
    handles.removeAll(keepingCapacity: false)
    return .closed
  }

  private func openAttachment(
    locator: DesignDatabaseLocator,
    expectedDatabaseID: DesignDatabaseID,
    operation: DesignDatabaseRuntimeGenesisRequest?
  ) async throws(DesignDatabaseError) -> DesignDatabaseRuntimeAttachment {
    do {
      return try await DesignDatabaseRuntimeAttacher(
        containerProvider: containerProvider
      ).open(locator: locator, registration: registration)
    } catch let error {
      throw Self.map(
        error,
        locator: locator,
        expectedDatabaseID: expectedDatabaseID,
        operation: operation
      )
    }
  }

  private func requireOpen() throws(DesignDatabaseError) {
    guard !isClosed else { throw .closed }
  }

  private static func map(
    _ error: DesignDatabaseRuntimeError,
    locator: DesignDatabaseLocator,
    expectedDatabaseID: DesignDatabaseID?,
    operation request: DesignDatabaseRuntimeGenesisRequest?
  ) -> DesignDatabaseError {
    switch error {
    case .databaseNotFound:
      return .databaseNotFound(locator)
    case .databaseAlreadyExists:
      return .databaseAlreadyExists(locator)
    case .databaseIdentityMismatch(let expected, let actual):
      do {
        return .databaseIdentityMismatch(
          expected: try DesignDatabaseID(hexadecimalValue: expected),
          actual: try DesignDatabaseID(hexadecimalValue: actual)
        )
      } catch {
        return .corruption("Runtime returned a malformed database identity.")
      }
    case .runtimeRegistrationMismatch, .containerSchemaMismatch,
         .genesisRequestBindingMismatch:
      return .runtimeRegistrationMismatch
    case .missingFeatureCapability(let rawValue),
         .incompatibleFeatureCapability(let rawValue):
      do {
        return .unsupportedCapability(try DesignCapabilityID(rawValue: rawValue))
      } catch {
        return .corruption("Runtime returned a malformed capability identifier.")
      }
    case .creationIdempotencyConflict:
      guard let request else {
        return .corruption("An idempotency conflict omitted its creation request.")
      }
      return .idempotencyConflict(
        operation: DesignDatabaseOperationReference(
          databaseID: request.databaseID,
          authorizationSubjectScopeID: request.authorizationSubjectScopeID,
          operationID: request.operationID
        )
      )
    case .generationExhausted(let kind):
      return .generationExhausted(kind: kind)
    case .revisionNotFound(let rawValue):
      guard let expectedDatabaseID else {
        return .corruption("A missing revision omitted its database identity.")
      }
      do {
        return .revisionNotFound(
          DesignRevisionReference(
            databaseID: expectedDatabaseID,
            revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
          )
        )
      } catch {
        return .corruption("Runtime returned a malformed revision identity.")
      }
    case .revisionDeleting(let rawValue):
      guard let expectedDatabaseID else {
        return .corruption("A deleting revision omitted its database identity.")
      }
      do {
        return .revisionDeleting(
          DesignRevisionReference(
            databaseID: expectedDatabaseID,
            revisionID: try DesignRevisionID(hexadecimalValue: rawValue)
          )
        )
      } catch {
        return .corruption("Runtime returned a malformed deleting revision identity.")
      }
    case .revisionCollected(let rawValue):
      guard let expectedDatabaseID else {
        return .corruption("A collected revision omitted its database identity.")
      }
      do {
        return .revisionCollected(
          DesignRevisionReference(
            databaseID: expectedDatabaseID,
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
    case .invalidContributionIdentifier, .emptyContribution,
         .duplicateContribution, .duplicateDesignSchema, .duplicateEntity,
         .contributionEntityRuntimeMismatch, .mutationAdapterBindingMismatch,
         .duplicateMutationAdapter, .invalidPhysicalWriteReclaimer,
         .duplicatePhysicalWriteReclaimer,
         .physicalWriteReclaimerUnavailable,
         .physicalWriteReclaimFailed, .schemaConstructionFailed,
         .frameworkConfigurationFailed, .registrationDigestFailed,
         .containerProviderFailed, .creationTransactionFailed,
         .referenceIdempotencyConflict, .referenceTransactionFailed,
         .namedReferenceNotFound,
         .commitAbandonmentIdempotencyConflict,
         .commitAbandonmentTransactionFailed,
         .commitIdempotencyConflict, .commitStagingConflict,
         .disjointMergeIdempotencyConflict,
         .validatedMutationDirectoryBudgetExceeded,
         .preparedMutationDirectoryBudgetExceeded,
         .stagingPhysicalIdentityDirectoryBudgetExceeded,
         .commitSubmissionCapsuleBudgetExceeded,
         .commitRecoveryIntentBudgetExceeded,
         .deletionCandidateBudgetExceeded,
         .collectionRecoveryIntentBudgetExceeded,
         .collectionRootAuditBudgetExceeded,
         .collectionReachabilityChanged,
         .revisionStillReachable,
         .collectionIdempotencyConflict,
         .physicalIdentityDirectoryNotFound,
         .physicalWriteDeleting,
         .commitTransactionFailed:
      return .persistence(String(describing: error))
    case .retentionTransactionFailed:
      return .persistence(String(describing: error))
    }
  }

}
