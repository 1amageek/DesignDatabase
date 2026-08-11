import CircuiteFoundation
import CircuiteFoundationCrypto
import Database
import DesignDatabaseCore
import DesignDatabaseRuntime
import Foundation
import Synchronization
import Testing

@Persistable
private struct RuntimeTestLogicEntity {
  #Directory<RuntimeTestLogicEntity>("design-database", "runtime-test-logic")

  var id: String = ""
  var name: String = ""
}

@Persistable
private struct RuntimeTestLayoutEntity {
  #Directory<RuntimeTestLayoutEntity>("design-database", "runtime-test-layout")

  var id: String = ""
  var layer: Int64 = 0
}

private struct RuntimeTestMutationAdapter: DesignDatabaseRuntimeMutationAdapter {
  let schemaID: DesignSchemaID
  let schemaVersion = SchemaVersion.v1
  let adapterVersion = "1.0.0"
  let supportedFacets: Set<DesignFacetID>

  init() throws {
    schemaID = try DesignSchemaID(rawValue: "lsi.logic")
    supportedFacets = [
      try DesignFacetID(rawValue: "logic"),
      try DesignFacetID(rawValue: "power"),
    ]
  }

  func validate(
    _ segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationValidation
  ) async throws(DesignDatabaseRuntimeMutationAdapterError)
    -> DesignDatabaseRuntimeValidatedMutation {
    if RequestAuthorization.context.principal?.roles.contains(
      DesignDatabaseRuntimeStorageSecurity.administratorRole
    ) == true {
      throw .invalidPayload(
        reason: "The domain validator inherited the internal storage role."
      )
    }
    let name = String(decoding: segment.payload, as: UTF8.self)
    if name == "reject" {
      let diagnostic = DesignDiagnostic(
        code: .trusted("RUNTIME_TEST_REJECTION"),
        severity: .error,
        summary: "The test adapter rejected the proposed name."
      )
      throw .validationFailed(
        diagnostics: [diagnostic],
        diagnosticsDigest: segment.payloadDigest
      )
    }
    _ = context
    return DesignDatabaseRuntimeValidatedMutation(
      segmentID: segment.id,
      materializationPayload: segment.payload
    )
  }

  func materializeValidatedMutation(
    _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
    for segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationRestoration
  ) throws(DesignDatabaseRuntimeMutationAdapterError)
    -> any DesignDatabaseRuntimePreparedMutation
  {
    var name = String(
      decoding: validation.materializationPayload,
      as: UTF8.self
    )
    if !segment.identityPlan.isEmpty {
      guard let assignments = context.identityAssignments(for: segment.id) else {
        throw .invalidPayload(reason: "The persisted identity assignments are unavailable.")
      }
      name = assignments.entities.map(\.permanentID.description)
        .joined(separator: ",")
        + "|"
        + assignments.relationOccurrences.map(\.permanentID.description)
          .joined(separator: ",")
    }
    return RuntimeTestPreparedMutation(
      segmentID: validation.segmentID,
      model: RuntimeTestLogicEntity(
        id: context.candidateRevision.revisionID.description,
        name: name
      ),
      facetRootDigest: segment.payloadDigest,
      changeContributionDigest: segment.payloadDigest
    )
  }
}

private struct RuntimeTestPreparedMutation: DesignDatabaseRuntimePreparedMutation {
  let segmentID: DesignMutationPlanSegmentID
  let model: RuntimeTestLogicEntity
  let facetRootDigest: ContentDigest
  let changeContributionDigest: ContentDigest
  let writeCount: UInt64 = 1

  func immutableWriteIdentity(
    at index: UInt64
  ) throws(DesignDatabaseRuntimePreparedMutationError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    guard index == 0 else {
      throw .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    return try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1",
      modelID: model.id
    )
  }

  func stageImmutableWrite(
    at index: UInt64,
    to transaction: any DatabaseTransactionWriting
  ) async throws {
    guard index == 0 else {
      throw DesignDatabaseRuntimePreparedMutationError
        .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    try await transaction.save(model, precondition: .notExists)
  }
}

private struct RuntimeTestPhysicalWriteReclaimer:
  DesignDatabaseRuntimePhysicalWriteReclaimer
{
  let storageType = "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1"

  func deleteImmutableWrite(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    from transaction: any DatabaseTransactionWriting
  ) async throws(DesignDatabaseRuntimePhysicalWriteReclaimerError) {
    _ = try DesignDatabaseRuntimePhysicalWriteDeletion
      .requirePartitionComponents(
        identity,
        storageType: storageType,
        count: 0
      )
    try await DesignDatabaseRuntimePhysicalWriteDeletion.delete(
      identity,
      model: RuntimeTestLogicEntity.self,
      identifiedBy: identity.modelID,
      in: DirectoryPath<RuntimeTestLogicEntity>(),
      expectedIdentity: { model in
        try DesignDatabaseRuntimeImmutableWriteIdentity(
          storageType: storageType,
          modelID: model.id
        )
      },
      from: transaction
    )
  }
}

private struct RuntimeTestDuplicateIdentityPreparedMutation:
  DesignDatabaseRuntimePreparedMutation
{
  let segmentID: DesignMutationPlanSegmentID
  let model: RuntimeTestLogicEntity
  let facetRootDigest: ContentDigest
  let changeContributionDigest: ContentDigest
  let writeCount: UInt64 = 2

  func immutableWriteIdentity(
    at index: UInt64
  ) throws(DesignDatabaseRuntimePreparedMutationError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    guard index < writeCount else {
      throw .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    return try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "DesignDatabaseRuntimeTests.DuplicateIdentity.v1",
      modelID: model.id
    )
  }

  func stageImmutableWrite(
    at index: UInt64,
    to transaction: any DatabaseTransactionWriting
  ) async throws {
    guard index < writeCount else {
      throw DesignDatabaseRuntimePreparedMutationError
        .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    try await transaction.save(model, precondition: .notExists)
  }
}

private struct RuntimeTestProjectedMutationAdapter:
  DesignDatabaseRuntimeMutationAdapter
{
  let schemaID: DesignSchemaID
  let schemaVersion = SchemaVersion.v1
  let adapterVersion = "1.0.0"
  let supportedFacets: Set<DesignFacetID>

  init() throws {
    schemaID = try DesignSchemaID(rawValue: "lsi.logic")
    supportedFacets = [try DesignFacetID(rawValue: "logic")]
  }

  func materializeValidatedMutation(
    _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
    for segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationRestoration
  ) throws(DesignDatabaseRuntimeMutationAdapterError)
    -> any DesignDatabaseRuntimePreparedMutation
  {
    let mode = String(
      decoding: validation.materializationPayload,
      as: UTF8.self
    )
    let projectionChanges: [DesignProjectionChange]
    do {
      switch mode {
      case "bootstrap":
        guard let assignments = context.identityAssignments(for: segment.id),
              assignments.entities.count == 1,
              let entityID = assignments.entities.first?.permanentID else {
          throw DesignDatabaseRuntimeMutationAdapterError.invalidPayload(
            reason: "Entity bootstrap requires one reserved identity."
          )
        }
        let entry = try DesignEntityProjectionRecord(
          entityID: entityID,
          facetID: segment.targetFacet,
          kindID: DesignEntityKindID(rawValue: "module"),
          contentDigest: context.designSchemaBundleDigest
        ).projectionEntry()
        projectionChanges = [
          try DesignProjectionChange(
            family: .entity,
            before: nil,
            after: entry
          ),
        ]
      case "inherit":
        projectionChanges = []
      case "update":
        let entityID = try DesignEntityID(rawValue: 1)
        let before = try DesignEntityProjectionRecord(
          entityID: entityID,
          facetID: segment.targetFacet,
          kindID: DesignEntityKindID(rawValue: "module"),
          contentDigest: context.designSchemaBundleDigest
        ).projectionEntry()
        let after = try DesignEntityProjectionRecord(
          entityID: entityID,
          facetID: segment.targetFacet,
          kindID: DesignEntityKindID(rawValue: "module"),
          contentDigest: context.dependencyRootDigest
        ).projectionEntry()
        projectionChanges = [
          try DesignProjectionChange(
            family: .entity,
            before: before,
            after: after
          ),
        ]
      case "stale":
        let entityID = try DesignEntityID(rawValue: 1)
        let before = try DesignEntityProjectionRecord(
          entityID: entityID,
          facetID: segment.targetFacet,
          kindID: DesignEntityKindID(rawValue: "module"),
          contentDigest: segment.payloadDigest
        ).projectionEntry()
        let after = try DesignEntityProjectionRecord(
          entityID: entityID,
          facetID: segment.targetFacet,
          kindID: DesignEntityKindID(rawValue: "module"),
          contentDigest: context.semanticDependencyGraphDigest
        ).projectionEntry()
        projectionChanges = [
          try DesignProjectionChange(
            family: .entity,
            before: before,
            after: after
          ),
        ]
      case "bulk":
        guard let assignments = context.identityAssignments(for: segment.id),
              assignments.entities.count == 130 else {
          throw DesignDatabaseRuntimeMutationAdapterError.invalidPayload(
            reason: "Entity bulk insertion requires 130 reserved identities."
          )
        }
        projectionChanges = try assignments.entities.map { assignment in
          let entry = try DesignEntityProjectionRecord(
            entityID: assignment.permanentID,
            facetID: segment.targetFacet,
            kindID: DesignEntityKindID(rawValue: "module"),
            contentDigest: context.designSchemaBundleDigest
          ).projectionEntry()
          return try DesignProjectionChange(
            family: .entity,
            before: nil,
            after: entry
          )
        }
      case "bulk-delete":
        projectionChanges = try (2..<128).map { rawID in
          let entry = try DesignEntityProjectionRecord(
            entityID: DesignEntityID(rawValue: UInt64(rawID)),
            facetID: segment.targetFacet,
            kindID: DesignEntityKindID(rawValue: "module"),
            contentDigest: context.designSchemaBundleDigest
          ).projectionEntry()
          return try DesignProjectionChange(
            family: .entity,
            before: entry,
            after: nil
          )
        }
      default:
        throw DesignDatabaseRuntimeMutationAdapterError.invalidPayload(
          reason: "Unknown projected mutation test mode."
        )
      }
    } catch let error as DesignDatabaseRuntimeMutationAdapterError {
      throw error
    } catch {
      throw .invalidPayload(
        reason: "Projected mutation preparation failed: \(error)"
      )
    }
    return RuntimeTestProjectedPreparedMutation(
      segmentID: segment.id,
      model: RuntimeTestLogicEntity(
        id: context.candidateRevision.revisionID.description,
        name: mode
      ),
      facetRootDigest: segment.payloadDigest,
      changeContributionDigest: segment.payloadDigest,
      projectionChanges: projectionChanges
    )
  }

  func validate(
    _ segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationValidation
  ) async throws(DesignDatabaseRuntimeMutationAdapterError)
    -> DesignDatabaseRuntimeValidatedMutation
  {
    let mode = String(decoding: segment.payload, as: UTF8.self)
    guard [
      "bootstrap", "inherit", "update", "stale", "bulk", "bulk-delete",
    ].contains(mode) else {
      throw .invalidPayload(reason: "Unknown projected mutation test mode.")
    }
    _ = context
    return DesignDatabaseRuntimeValidatedMutation(
      segmentID: segment.id,
      materializationPayload: segment.payload
    )
  }
}

private struct RuntimeTestProjectedPreparedMutation:
  DesignDatabaseRuntimePreparedMutation
{
  let segmentID: DesignMutationPlanSegmentID
  let model: RuntimeTestLogicEntity
  let facetRootDigest: ContentDigest
  let changeContributionDigest: ContentDigest
  let projectionChanges: [DesignProjectionChange]
  let writeCount: UInt64 = 1

  func immutableWriteIdentity(
    at index: UInt64
  ) throws(DesignDatabaseRuntimePreparedMutationError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    guard index == 0 else {
      throw .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    return try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1",
      modelID: model.id
    )
  }

  func stageImmutableWrite(
    at index: UInt64,
    to transaction: any DatabaseTransactionWriting
  ) async throws {
    guard index == 0 else {
      throw DesignDatabaseRuntimePreparedMutationError
        .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    try await transaction.save(model, precondition: .notExists)
  }
}

private enum RuntimeTestStagingInterruption: Error {
  case injected
}

private actor RuntimeTestStagingFailureGate {
  private let failureIndex: UInt64
  private var didFail = false

  init(failureIndex: UInt64) {
    self.failureIndex = failureIndex
  }

  func interruptIfNeeded(at index: UInt64) throws {
    guard index == failureIndex, !didFail else { return }
    didFail = true
    throw RuntimeTestStagingInterruption.injected
  }
}

private final class RuntimeTestPreparationCounter: Sendable {
  private struct State: Sendable {
    var validationCount = 0
    var materializationCount = 0
  }

  private let state = Mutex(State())

  func recordValidation() {
    state.withLock { $0.validationCount += 1 }
  }

  func recordMaterialization() {
    state.withLock { $0.materializationCount += 1 }
  }

  func counts() -> (validation: Int, materialization: Int) {
    state.withLock { ($0.validationCount, $0.materializationCount) }
  }
}

private final class RuntimeTestMaterializationFailureGate: Sendable {
  private let didInterrupt = Mutex(false)

  func interruptOnce() throws(DesignDatabaseRuntimeMutationAdapterError) {
    let shouldInterrupt = didInterrupt.withLock { state in
      guard !state else { return false }
      state = true
      return true
    }
    guard !shouldInterrupt else {
      throw .invalidPayload(reason: "Injected materialization interruption.")
    }
  }
}

private struct RuntimeTestPreIntentMutationAdapter:
  DesignDatabaseRuntimeMutationAdapter
{
  let schemaID: DesignSchemaID
  let schemaVersion = SchemaVersion.v1
  let adapterVersion = "1.0.0"
  let supportedFacets: Set<DesignFacetID>

  private let counter: RuntimeTestPreparationCounter
  private let failureGate: RuntimeTestMaterializationFailureGate

  init(
    counter: RuntimeTestPreparationCounter,
    failureGate: RuntimeTestMaterializationFailureGate
  ) throws {
    schemaID = try DesignSchemaID(rawValue: "lsi.logic")
    supportedFacets = [try DesignFacetID(rawValue: "logic")]
    self.counter = counter
    self.failureGate = failureGate
  }

  func validate(
    _ segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationValidation
  ) async throws(DesignDatabaseRuntimeMutationAdapterError)
    -> DesignDatabaseRuntimeValidatedMutation
  {
    _ = context
    counter.recordValidation()
    return DesignDatabaseRuntimeValidatedMutation(
      segmentID: segment.id,
      materializationPayload: segment.payload
    )
  }

  func materializeValidatedMutation(
    _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
    for segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationRestoration
  ) throws(DesignDatabaseRuntimeMutationAdapterError)
    -> any DesignDatabaseRuntimePreparedMutation
  {
    counter.recordMaterialization()
    try failureGate.interruptOnce()
    return RuntimeTestPreparedMutation(
      segmentID: validation.segmentID,
      model: RuntimeTestLogicEntity(
        id: context.candidateRevision.revisionID.description,
        name: String(
          decoding: validation.materializationPayload,
          as: UTF8.self
        )
      ),
      facetRootDigest: segment.payloadDigest,
      changeContributionDigest: segment.payloadDigest
    )
  }
}

private struct RuntimeTestResumableMutationAdapter:
  DesignDatabaseRuntimeMutationAdapter
{
  let schemaID: DesignSchemaID
  let schemaVersion = SchemaVersion.v1
  let adapterVersion = "1.0.0"
  let supportedFacets: Set<DesignFacetID>

  private let writeCount: UInt64
  private let failureGate: RuntimeTestStagingFailureGate
  private let preparationCounter: RuntimeTestPreparationCounter

  init(
    writeCount: UInt64,
    failureGate: RuntimeTestStagingFailureGate,
    preparationCounter: RuntimeTestPreparationCounter
  ) throws {
    schemaID = try DesignSchemaID(rawValue: "lsi.logic")
    supportedFacets = [try DesignFacetID(rawValue: "logic")]
    self.writeCount = writeCount
    self.failureGate = failureGate
    self.preparationCounter = preparationCounter
  }

  func validate(
    _ segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationValidation
  ) async throws(DesignDatabaseRuntimeMutationAdapterError)
    -> DesignDatabaseRuntimeValidatedMutation
  {
    _ = context
    preparationCounter.recordValidation()
    return DesignDatabaseRuntimeValidatedMutation(
      segmentID: segment.id,
      materializationPayload: segment.payload
    )
  }

  func materializeValidatedMutation(
    _ validation: DesignDatabaseRuntimeValidatedMutationRecord,
    for segment: DesignMutationPlanSegment,
    in context: DesignDatabaseRuntimeMutationRestoration
  ) throws(DesignDatabaseRuntimeMutationAdapterError)
    -> any DesignDatabaseRuntimePreparedMutation
  {
    preparationCounter.recordMaterialization()
    return RuntimeTestResumablePreparedMutation(
      segmentID: validation.segmentID,
      candidateRevisionID: context.candidateRevision.revisionID.description,
      writeCount: writeCount,
      facetRootDigest: segment.payloadDigest,
      changeContributionDigest: segment.payloadDigest,
      failureGate: failureGate
    )
  }
}

private struct RuntimeTestResumablePreparedMutation:
  DesignDatabaseRuntimePreparedMutation
{
  let segmentID: DesignMutationPlanSegmentID
  let candidateRevisionID: String
  let writeCount: UInt64
  let facetRootDigest: ContentDigest
  let changeContributionDigest: ContentDigest
  let failureGate: RuntimeTestStagingFailureGate

  func immutableWriteIdentity(
    at index: UInt64
  ) throws(DesignDatabaseRuntimePreparedMutationError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    guard index < writeCount else {
      throw .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    return try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1",
      modelID: candidateRevisionID + "-" + String(index)
    )
  }

  func stageImmutableWrite(
    at index: UInt64,
    to transaction: any DatabaseTransactionWriting
  ) async throws {
    guard index < writeCount else {
      throw DesignDatabaseRuntimePreparedMutationError
        .invalidImmutableWriteIndex(index: index, writeCount: writeCount)
    }
    try await failureGate.interruptIfNeeded(at: index)
    try await transaction.save(
      RuntimeTestLogicEntity(
        id: candidateRevisionID + "-" + String(index),
        name: "staged-" + String(index)
      ),
      precondition: .notExists
    )
  }
}

@Suite("DesignDatabase runtime registration")
struct DesignDatabaseRuntimeRegistrationTests {
  @Test("Immutable physical identities are bounded and collision-safe")
  func immutablePhysicalIdentityContract() throws {
    let first = try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "RuntimeTestEntity.v1",
      partitionComponents: ["logic", "sha256:1111"],
      modelID: "page-1"
    )
    let second = try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "RuntimeTestEntity.v1",
      partitionComponents: ["logic", "sha256:2222"],
      modelID: "page-1"
    )
    #expect(first != second)
    #expect(first.canonicalBytes != second.canonicalBytes)
    #expect([second, first].sorted() == [first, second])

    #expect(throws: DesignDatabaseRuntimePreparedMutationError.self) {
      _ = try DesignDatabaseRuntimeImmutableWriteIdentity(
        storageType: String(
          repeating: "x",
          count: Int(
            DesignDatabaseRuntimeImmutableWriteIdentity
              .maximumComponentByteCount + 1
          )
        ),
        modelID: "page-1"
      )
    }
    #expect(throws: DesignDatabaseRuntimePreparedMutationError.self) {
      _ = try DesignDatabaseRuntimeImmutableWriteIdentity(
        storageType: "RuntimeTestEntity.v1",
        partitionComponents: Array(
          repeating: "partition",
          count: Int(
            DesignDatabaseRuntimeImmutableWriteIdentity.maximumPartitionCount + 1
          )
        ),
        modelID: "page-1"
      )
    }
  }

  @Test("Prepared mutation records reject duplicate physical identities")
  func preparedMutationRecordRejectsDuplicatePhysicalIdentities() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let baseRevision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 1)
    )
    let submission = try mutationSubmission(
      operation: "duplicate-physical-identity",
      payload: Array("duplicate".utf8),
      databaseID: databaseID,
      baseRevision: baseRevision,
      schemaBundleDigest: digest(repeating: "1"),
      dependencyRootDigest: digest(repeating: "2"),
      dependencyGraphDigest: digest(repeating: "3"),
      expectedWriteCount: 2
    )
    let segment = try #require(submission.plan.segments.first)
    let mutation = RuntimeTestDuplicateIdentityPreparedMutation(
      segmentID: segment.id,
      model: RuntimeTestLogicEntity(id: "duplicate-page", name: "duplicate"),
      facetRootDigest: segment.payloadDigest,
      changeContributionDigest: segment.payloadDigest
    )
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimePreparedMutationDirectory(
        segments: [segment],
        prepared: [mutation],
        using: SHA256ContentDigester()
      )
    }
  }

  @Test("Physical collection claims authenticate identity and state")
  func physicalCollectionClaimAuthentication() throws {
    let identity = try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "RuntimeTestEntity.v1",
      partitionComponents: ["logic"],
      modelID: "page-1"
    )
    let digester = SHA256ContentDigester()
    let claim = try DesignDatabaseRuntimePhysicalCollectionClaim.makeClaimed(
      identity: identity,
      collectionIntentID: "collection:test",
      using: digester
    )
    #expect(
      try DesignDatabaseRuntimePhysicalCollectionClaim.validate(
        claim,
        expectedIdentity: identity,
        using: digester
      ) == .claimed
    )

    var tampered = claim
    tampered.collectionIntentID = "collection:tampered"
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimePhysicalCollectionClaim.validate(
        tampered,
        expectedIdentity: identity,
        using: digester
      )
    }
  }

  @Test("Revision lifecycle permits only visible-deleting-collected transitions")
  func revisionLifecycleTransitions() throws {
    let revision = DesignRevisionReference(
      databaseID: try DesignDatabaseID(high: 5, low: 6),
      revisionID: DesignRevisionID(high: 7, low: 8)
    )
    let digester = SHA256ContentDigester()
    let visible = try DesignDatabaseRuntimeRevisionLifecycle.makeVisible(
      revision: revision,
      reachabilityGeneration: 0,
      using: digester
    )
    #expect(
      try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
        visible,
        revision: revision,
        using: digester
      ) == .visible
    )
    let deleting = try DesignDatabaseRuntimeRevisionLifecycle.transitioned(
      visible,
      revision: revision,
      from: .visible,
      to: .deleting,
      reachabilityGeneration: 1,
      using: digester
    )
    #expect(throws: DesignDatabaseRuntimeError.revisionDeleting(
      revision.revisionID.description
    )) {
      try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
        deleting,
        revision: revision,
        using: digester
      )
    }
    let collected = try DesignDatabaseRuntimeRevisionLifecycle.transitioned(
      deleting,
      revision: revision,
      from: .deleting,
      to: .collected,
      reachabilityGeneration: 2,
      using: digester
    )
    #expect(throws: DesignDatabaseRuntimeError.revisionCollected(
      revision.revisionID.description
    )) {
      try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
        collected,
        revision: revision,
        using: digester
      )
    }
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimeRevisionLifecycle.transitioned(
        collected,
        revision: revision,
        from: .collected,
        to: .visible,
        reachabilityGeneration: 3,
        using: digester
      )
    }
  }

  @Test("Snapshot lease coordinator owns pending, active, and released lifetimes")
  func snapshotLeaseCoordinatorLifetime() async throws {
    let coordinator = DesignDatabaseRuntimeLeaseCoordinator()
    let revision = DesignRevisionReference(
      databaseID: try DesignDatabaseID(high: 1, low: 2),
      revisionID: DesignRevisionID(high: 3, low: 4)
    )
    let pending = try await coordinator.registerPending(revision: revision)
    var observation = try await coordinator.observation()
    #expect(observation.generation == 1)
    #expect(observation.pendingLeaseCount == 1)
    #expect(observation.activeLeaseCount == 0)
    #expect(observation.deletionAdmissionCount == 0)

    let bindings = try DesignProjectionMaterializationBindingSet([])
    try await coordinator.activate(
      pending,
      materializationBindings: bindings
    )
    observation = try await coordinator.observation()
    #expect(observation.generation == 2)
    #expect(observation.pendingLeaseCount == 0)
    #expect(observation.activeLeaseCount == 1)
    #expect(observation.deletionAdmissionCount == 0)
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      try await coordinator.activate(
        pending,
        materializationBindings: bindings
      )
    }

    await coordinator.release(pending)
    observation = try await coordinator.observation()
    #expect(observation.generation == 3)
    #expect(observation.pendingLeaseCount == 0)
    #expect(observation.activeLeaseCount == 0)
    #expect(observation.deletionAdmissionCount == 0)
    await coordinator.release(pending)
    #expect(try await coordinator.observation() == observation)

    await coordinator.close()
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await coordinator.registerPending(revision: revision)
    }
  }

  @Test("Snapshot open rejects a missing revision-owned physical identity directory")
  func snapshotRejectsMissingRevisionPhysicalIdentityDirectory() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "snapshot-physical-directory-create",
      genesisLow: 201
    )
    _ = try await attachment.createGenesis(create)
    let revision = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let context = try await attachment.context()
    try await context.withTransaction { transaction in
      guard let directory = try await transaction.fetch(
        DesignRevisionPhysicalIdentityDirectoryModel.self,
        identifiedBy: revision.revisionID.description,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The corruption fixture has no revision physical directory."
        )
      }
      try await transaction.delete(directory, precondition: .exists)
    }
    do {
      _ = try await attachment.snapshotDescriptor(
        at: revision,
        expectedDatabaseID: create.databaseID
      )
      Issue.record("Snapshot open accepted a missing revision physical directory.")
    } catch let error {
      guard case .persistedStateCorrupt(let reason) = error else {
        Issue.record("Snapshot open returned the wrong typed failure: \(error)")
        _ = await attachment.close()
        return
      }
      #expect(reason.contains("owned physical identity directory"))
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Deletion admission is candidate-scoped and fences new leases")
  func deletionAdmissionFencesOnlyItsCandidates() async throws {
    let coordinator = DesignDatabaseRuntimeLeaseCoordinator()
    let databaseID = try DesignDatabaseID(high: 11, low: 12)
    let firstRevision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 13, low: 14)
    )
    let secondRevision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 15, low: 16)
    )
    let firstCandidates = try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
      revisions: [firstRevision]
    )
    let firstLease = try await coordinator.registerPending(
      revision: firstRevision
    )
    await #expect(throws: DesignDatabaseRuntimeError.revisionDeleting(
      firstRevision.revisionID.description
    )) {
      _ = try await coordinator.admitDeletion(
        identifier: "collection:first",
        candidates: firstCandidates
      )
    }
    await coordinator.release(firstLease)

    let token = try await coordinator.admitDeletion(
      identifier: "collection:first",
      candidates: firstCandidates
    )
    let repeatedToken = try await coordinator.admitDeletion(
      identifier: "collection:first",
      candidates: firstCandidates
    )
    #expect(repeatedToken == token)
    var observation = try await coordinator.observation()
    #expect(observation.deletionAdmissionCount == 1)
    await #expect(throws: DesignDatabaseRuntimeError.revisionDeleting(
      firstRevision.revisionID.description
    )) {
      _ = try await coordinator.registerPending(revision: firstRevision)
    }

    let unrelatedLease = try await coordinator.registerPending(
      revision: secondRevision
    )
    await coordinator.release(unrelatedLease)
    try await coordinator.releaseDeletionAdmission(token)
    observation = try await coordinator.observation()
    #expect(observation.deletionAdmissionCount == 0)
    let reopenedLease = try await coordinator.registerPending(
      revision: firstRevision
    )
    await coordinator.release(reopenedLease)
  }

  @Test("Collection recovery authenticates intent and restores deletion admission")
  func collectionRecoveryRestoresDeletionAdmission() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "collection-recovery-create",
      genesisLow: 44
    )
    _ = try await attachment.createGenesis(create)
    let revision = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collection-recovery-admission"
      )
    )
    let requestDigest = try digest(repeating: "8")
    let rootSetDigest = try digest(repeating: "9")
    let physicalRootSetDigest = try digest(repeating: "a")
    let physicalIdentityDirectory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        identities: [],
        maximumIdentityCount: 256,
        using: SHA256ContentDigester()
      )
    let candidates = try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
      revisions: [revision]
    )
    let intent = try DesignDatabaseRuntimeCollectionIntent.makeAdmitted(
      operation: operation,
      requestDigest: requestDigest,
      candidates: candidates,
      originalRootSetDigest: rootSetDigest,
      physicalRootSetDigest: physicalRootSetDigest,
      physicalIdentityDirectoryDigest: physicalIdentityDirectory.digest,
      physicalIdentityCount: 0,
      observedReachabilityGeneration: 0,
      admittedReachabilityGeneration: 1,
      leaseObservationGeneration: 0,
      using: SHA256ContentDigester()
    )
    let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
      intent,
      using: SHA256ContentDigester()
    )
    #expect(recovered.operation == operation)
    #expect(recovered.requestDigest == requestDigest)
    #expect(recovered.candidates == candidates)
    #expect(recovered.originalRootSetDigest == rootSetDigest)
    #expect(recovered.physicalRootSetDigest == physicalRootSetDigest)
    #expect(
      recovered.physicalIdentityDirectoryDigest
        == physicalIdentityDirectory.digest
    )
    #expect(recovered.physicalIdentityCount == 0)
    #expect(recovered.state == .admitted)

    let context = try await attachment.context()
    try await context.withTransaction { transaction in
      let reachability = try await DesignDatabaseRuntimeReachability.require(
        databaseID: create.databaseID,
        transaction: transaction
      )
      let advancedReachability = try DesignDatabaseRuntimeReachability.advanced(
        reachability,
        kind: "reachability"
      )
      guard let visibleLifecycle = try await transaction.fetch(
        DesignRevisionLifecycleModel.self,
        identifiedBy: revision.revisionID.description,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The collection recovery fixture has no visible lifecycle."
        )
      }
      let deletingLifecycle = try DesignDatabaseRuntimeRevisionLifecycle
        .transitioned(
          visibleLifecycle,
          revision: revision,
          from: .visible,
          to: .deleting,
          reachabilityGeneration: advancedReachability.generation,
          using: SHA256ContentDigester()
        )
      try await transaction.save(
        DesignDatabaseRuntimeOperationClaim.make(
          operation: operation,
          kind: DesignDatabaseRuntimeOperationClaim.collectionKind,
          requestDigest: requestDigest
        ),
        precondition: .notExists
      )
      try await transaction.save(intent, precondition: .notExists)
      try await transaction.save(
        physicalIdentityDirectory.model(
          operation: operation,
          requestDigest: requestDigest
        ),
        precondition: .notExists
      )
      try await transaction.save(deletingLifecycle, precondition: .exists)
      try await transaction.save(advancedReachability, precondition: .exists)
    }
    try await attachment.restoreCollectionAdmissionsBeforeServingOpens()
    let observation = try await attachment.snapshotLeaseCoordinator.observation()
    #expect(observation.deletionAdmissionCount == 1)
    await #expect(throws: DesignDatabaseRuntimeError.revisionDeleting(
      revision.revisionID.description
    )) {
      _ = try await attachment.snapshotLeaseCoordinator.registerPending(
        revision: revision
      )
    }
    let unrelatedRevision = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: DesignRevisionID(high: 0, low: 45)
    )
    let unrelatedLease = try await attachment.snapshotLeaseCoordinator
      .registerPending(revision: unrelatedRevision)
    await attachment.snapshotLeaseCoordinator.release(unrelatedLease)

    var tamperedIntent = intent
    tamperedIntent.candidateRevisionIDs = unrelatedRevision.revisionID.description
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimeCollectionIntent.recover(
        tamperedIntent,
        using: SHA256ContentDigester()
      )
    }
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      try await attachment.restoreCollectionAdmissionsBeforeServingOpens(
        maximumIntentCount: 0
      )
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Collection admission protects roots and atomically fences an unreferenced candidate")
  func collectionAdmissionProtectsRootsAndFencesCandidate() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "collection-admission-create",
      genesisLow: 46
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let genesisCandidates = try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
      revisions: [genesis]
    )
    let protectedRequest = try DesignDatabaseRuntimeCollectionAdmissionRequest(
      operation: DesignDatabaseOperationReference(
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID,
        operationID: try DesignDatabaseOperationID(
          rawValue: "collection-admission-protected-root"
        )
      ),
      candidates: genesisCandidates,
      using: SHA256ContentDigester()
    )
    await #expect(throws: DesignDatabaseRuntimeError.revisionStillReachable(
      revisionID: genesis.revisionID.description,
      rootKind: "named-reference:main"
    )) {
      _ = try await attachment.admitRevisionCollection(protectedRequest)
    }

    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "collection-admission-candidate",
      payload: Array("collectable".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let receipt: DesignCommitReceipt
    switch try await attachment.submit(
      submission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("The collection candidate was rejected: \(rejection)")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The collection candidate commit outcome was unknown.")
      _ = await attachment.close()
      return
    }
    let candidateSet = try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
      revisions: [receipt.candidateRevision]
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collection-admission-candidate-delete"
      )
    )
    let request = try DesignDatabaseRuntimeCollectionAdmissionRequest(
      operation: operation,
      candidates: candidateSet,
      using: SHA256ContentDigester()
    )
    let boundedBudget = try DesignDatabaseRuntimeCollectionRootAuditBudget(
      maximumReferenceCount: 16,
      maximumRetentionCount: 16,
      maximumBuildIntentCount: 16,
      maximumManifestCount: 1,
      maximumGraphEdgeCount: 16,
      scanPageSize: 16,
      maximumGenerationRetryCount: 1
    )
    await #expect(throws: DesignDatabaseRuntimeError
      .collectionRootAuditBudgetExceeded(
        kind: "revision manifests",
        limit: 1,
        requested: 2
      )) {
      _ = try await attachment.admitRevisionCollection(
        request,
        budget: boundedBudget
      )
    }

    let admittedIntent: DesignCollectionIntentModel
    switch try await attachment.admitRevisionCollection(request) {
    case .admitted(let intent):
      admittedIntent = intent
    case .collected:
      Issue.record("A newly admitted collection was already terminal.")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The collection admission outcome was unknown.")
      _ = await attachment.close()
      return
    }
    let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
      admittedIntent,
      using: SHA256ContentDigester()
    )
    #expect(recovered.operation == operation)
    #expect(recovered.requestDigest == request.requestDigest)
    #expect(recovered.candidates == candidateSet)
    #expect(recovered.state == .admitted)
    #expect(
      admittedIntent.admittedReachabilityGeneration
        == admittedIntent.observedReachabilityGeneration + 1
    )

    let context = try await attachment.context()
    let persisted = try await context.withTransaction { transaction in
      let key = DesignDatabaseRuntimeOperationClaim.key(operation)
      let claim = try await transaction.fetch(
        DesignOperationClaimModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let intent = try await transaction.fetch(
        DesignCollectionIntentModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let lifecycle = try await transaction.fetch(
        DesignRevisionLifecycleModel.self,
        identifiedBy: receipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      let reachability = try await DesignDatabaseRuntimeReachability.require(
        databaseID: create.databaseID,
        transaction: transaction
      )
      let physicalDirectory = try await transaction.fetch(
        DesignCollectionPhysicalIdentityDirectoryModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      return (claim, intent, lifecycle, reachability, physicalDirectory)
    }
    #expect(persisted.0 != nil)
    #expect(persisted.1?.id == admittedIntent.id)
    #expect(persisted.1?.stateDigestValue == admittedIntent.stateDigestValue)
    #expect(
      persisted.3.generation == admittedIntent.admittedReachabilityGeneration
    )
    let physicalDirectory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        model: try #require(persisted.4),
        operation: operation,
        requestDigest: request.requestDigest,
        maximumIdentityCount: 256,
        using: SHA256ContentDigester()
      )
    #expect(!physicalDirectory.identities.isEmpty)
    #expect(
      recovered.physicalIdentityDirectoryDigest == physicalDirectory.digest
    )
    #expect(
      recovered.physicalIdentityCount
        == UInt64(physicalDirectory.identities.count)
    )
    #expect(
      try await DesignDatabaseRuntimeCollectionPhysicalClaimValidator.validate(
        directory: physicalDirectory,
        collectionIntentID: admittedIntent.id,
        context: context,
        using: SHA256ContentDigester()
      ).allSatisfy { $0 == .claimed }
    )
    let deletingLifecycle = try #require(persisted.2)
    #expect(
      try DesignDatabaseRuntimeRevisionLifecycle.validate(
        deletingLifecycle,
        revision: receipt.candidateRevision,
        using: SHA256ContentDigester()
      ) == .deleting
    )
    let observation = try await attachment.snapshotLeaseCoordinator.observation()
    #expect(observation.deletionAdmissionCount == 1)
    await #expect(throws: DesignDatabaseRuntimeError.revisionDeleting(
      receipt.candidateRevision.revisionID.description
    )) {
      _ = try await attachment.snapshotDescriptor(
        at: receipt.candidateRevision,
        expectedDatabaseID: create.databaseID
      )
    }
    _ = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )

    switch try await attachment.admitRevisionCollection(request) {
    case .admitted(let repeatedIntent):
      #expect(repeatedIntent.id == admittedIntent.id)
      #expect(repeatedIntent.stateDigestValue == admittedIntent.stateDigestValue)
    case .collected:
      Issue.record("An admission retry changed the collection state.")
    case .outcomeUnknown:
      Issue.record("An admission retry did not reconcile its persisted state.")
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Collection sweep deletes exact writes and publishes one terminal receipt")
  func collectionSweepDeletesExactWritesAndPublishesReceipt() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "collection-sweep-create",
      genesisLow: 47
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "collection-sweep-candidate",
      payload: Array("collectable-write".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let receipt: DesignCommitReceipt
    switch try await attachment.submit(
      submission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("The collection sweep candidate was rejected: \(rejection)")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The collection sweep candidate outcome was unknown.")
      _ = await attachment.close()
      return
    }
    let context = try await attachment.context()
    let rejectedOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collection-sweep-rejected-staging"
      )
    )
    let rejectedSubmission = DesignCommitSubmission(
      operationID: rejectedOperation.operationID,
      plan: submission.plan,
      requestDigest: submission.requestDigest
    )
    try await context.withTransaction { transaction in
      let committedKey = DesignDatabaseRuntimeOperationClaim.key(
        receipt.operation
      )
      guard let committedIntent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: committedKey,
        consistency: .serializable
      ), let committedPhysicalDirectoryModel = try await transaction.fetch(
        DesignStagingPhysicalIdentityDirectoryModel.self,
        identifiedBy: committedKey,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The rejected staging fixture has no committed source build."
        )
      }
      let preparedDirectoryDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: committedIntent.preparedDirectoryDigestAlgorithm
        ),
        hexadecimalValue: committedIntent.preparedDirectoryDigestValue
      )
      let stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: committedIntent.stagingDigestAlgorithm
        ),
        hexadecimalValue: committedIntent.stagingDigestValue
      )
      let committedPhysicalDirectory = try
        DesignDatabaseRuntimeStagingPhysicalIdentityDirectory(
          model: committedPhysicalDirectoryModel,
          operation: receipt.operation,
          requestDigest: receipt.requestDigest,
          planDigest: receipt.planDigest,
          candidateRevision: receipt.candidateRevision,
          using: SHA256ContentDigester()
        )
      let initialRejectedIntent = try
        DesignDatabaseRuntimeCommitBuildIntent.make(
          operation: rejectedOperation,
          submission: rejectedSubmission,
          candidateRevision: receipt.candidateRevision,
          preparedDirectoryDigest: preparedDirectoryDigest,
          preparedMutationCount: committedIntent.preparedMutationCount,
          stagingDigest: stagingDigest,
          expectedDomainWriteCount: committedIntent
            .expectedDomainWriteCount,
          expectedProjectionNodeCount: committedIntent
            .expectedProjectionNodeCount,
          using: SHA256ContentDigester()
        )
      let rejectedIntent = try DesignDatabaseRuntimeCommitBuildIntent
        .advanced(
          initialRejectedIntent,
          stagedDomainWriteCount: committedIntent
            .expectedDomainWriteCount,
          stagedProjectionNodeCount: committedIntent
            .expectedProjectionNodeCount,
          state: .rejected,
          using: SHA256ContentDigester()
        )
      let reachability = try await DesignDatabaseRuntimeReachability.require(
        databaseID: create.databaseID,
        transaction: transaction
      )
      let advancedReachability = try DesignDatabaseRuntimeReachability
        .advanced(reachability, kind: "rejected staging fixture")
      let activeRoot = try DesignDatabaseRuntimeStagingRoot.makeActive(
        operation: rejectedOperation,
        submission: rejectedSubmission,
        candidateRevision: receipt.candidateRevision,
        stagingDigest: stagingDigest,
        physicalIdentityDirectoryDigest: committedPhysicalDirectory.digest,
        reachabilityGeneration: reachability.generation,
        using: SHA256ContentDigester()
      )
      let rejectedRoot = try DesignDatabaseRuntimeStagingRoot.terminalized(
        activeRoot,
        state: .rejected,
        reachabilityGeneration: advancedReachability.generation,
        using: SHA256ContentDigester()
      )
      try await transaction.save(rejectedIntent, precondition: .notExists)
      try await transaction.save(
        rejectedRoot,
        precondition: .notExists
      )
      try await transaction.save(
        committedPhysicalDirectory.model(
          operation: rejectedOperation,
          submission: rejectedSubmission,
          candidateRevision: receipt.candidateRevision
        ),
        precondition: .notExists
      )
      try await transaction.save(
        advancedReachability,
        precondition: .exists
      )
    }
    let operation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collection-sweep-delete"
      )
    )
    let request = try DesignDatabaseRuntimeCollectionAdmissionRequest(
      operation: operation,
      candidates: try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
        revisions: [receipt.candidateRevision]
      ),
      using: SHA256ContentDigester()
    )
    let admittedIntent: DesignCollectionIntentModel
    switch try await attachment.admitRevisionCollection(request) {
    case .admitted(let intent):
      admittedIntent = intent
    case .collected:
      Issue.record("The collection sweep fixture was already collected.")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The collection sweep admission outcome was unknown.")
      _ = await attachment.close()
      return
    }

    let physicalDirectoryModel = try await context.withTransaction {
      transaction in
      try await transaction.fetch(
        DesignCollectionPhysicalIdentityDirectoryModel.self,
        identifiedBy: admittedIntent.id,
        consistency: .serializable
      )
    }
    let physicalDirectory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        model: try #require(physicalDirectoryModel),
        operation: operation,
        requestDigest: request.requestDigest,
        maximumIdentityCount: 256,
        using: SHA256ContentDigester()
      )
    #expect(!physicalDirectory.identities.isEmpty)
    #expect(
      physicalDirectory.rejectedStagingRootIDs
        == [DesignDatabaseRuntimeOperationClaim.key(rejectedOperation)]
    )
    let reclaimingRoot = try await context.withTransaction { transaction in
      try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(
          rejectedOperation
        ),
        consistency: .serializable
      )
    }
    #expect(
      try DesignDatabaseRuntimeRejectedStagingRoot.validate(
        try #require(reclaimingRoot),
        intent: try #require(
          try await context.withTransaction { transaction in
            try await transaction.fetch(
              DesignCommitBuildIntentModel.self,
              identifiedBy: DesignDatabaseRuntimeOperationClaim.key(
                rejectedOperation
              ),
              consistency: .serializable
            )
          }
        ),
        databaseID: create.databaseID,
        expectedState: .reclaiming,
        using: SHA256ContentDigester()
      ) == rejectedOperation
    )

    var terminalReceiptValue: DesignDatabaseRuntimeCollectionReceipt?
    var priorDeletedCount: UInt64 = 0
    for _ in 0...physicalDirectory.identities.count {
      switch try await attachment.sweepRevisionCollection(
        operation: operation,
        requestDigest: request.requestDigest,
        maximumPhysicalDeletionCount: 1
      ) {
      case .collected(let receipt):
        terminalReceiptValue = receipt
      case .sweeping(let progress):
        #expect(progress.deletedPhysicalIdentityCount > priorDeletedCount)
        priorDeletedCount = progress.deletedPhysicalIdentityCount
      case .outcomeUnknown:
        Issue.record("The collection sweep outcome was unknown.")
        _ = await attachment.close()
        return
      }
      if terminalReceiptValue != nil { break }
    }
    let terminalReceipt = try #require(terminalReceiptValue)
    #expect(terminalReceipt.operation == operation)
    #expect(terminalReceipt.requestDigest == request.requestDigest)
    #expect(terminalReceipt.candidates == request.candidates)
    #expect(
      terminalReceipt.physicalIdentityCount
        == UInt64(physicalDirectory.identities.count)
    )
    #expect(
      terminalReceipt.rejectedStagingRootIDs
        == physicalDirectory.rejectedStagingRootIDs
    )
    #expect(
      terminalReceipt.completedReachabilityGeneration
        > terminalReceipt.admittedReachabilityGeneration
    )

    let persisted = try await context.withTransaction { transaction in
      let domainModel = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: receipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      let intent = try await transaction.fetch(
        DesignCollectionIntentModel.self,
        identifiedBy: admittedIntent.id,
        consistency: .serializable
      )
      let lifecycle = try await transaction.fetch(
        DesignRevisionLifecycleModel.self,
        identifiedBy: receipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      let rejectedRoot = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(
          rejectedOperation
        ),
        consistency: .serializable
      )
      let rejectedIntent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(
          rejectedOperation
        ),
        consistency: .serializable
      )
      return (domainModel, intent, lifecycle, rejectedRoot, rejectedIntent)
    }
    #expect(persisted.0 == nil)
    let terminalIntent = try #require(persisted.1)
    let recovered = try DesignDatabaseRuntimeCollectionIntent.recover(
      terminalIntent,
      using: SHA256ContentDigester()
    )
    #expect(recovered.state == .collected)
    #expect(
      terminalIntent.deletedPhysicalIdentityCount
        == terminalIntent.physicalIdentityCount
    )
    #expect(
      try DesignDatabaseRuntimeRevisionLifecycle.validate(
        try #require(persisted.2),
        revision: receipt.candidateRevision,
        using: SHA256ContentDigester()
      ) == .collected
    )
    #expect(
      try DesignDatabaseRuntimeRejectedStagingRoot.validate(
        try #require(persisted.3),
        intent: try #require(persisted.4),
        databaseID: create.databaseID,
        expectedState: .reclaimed,
        using: SHA256ContentDigester()
      ) == rejectedOperation
    )
    #expect(
      try await DesignDatabaseRuntimeCollectionPhysicalClaimValidator.validate(
        directory: physicalDirectory,
        collectionIntentID: admittedIntent.id,
        context: context,
        using: SHA256ContentDigester()
      ).allSatisfy { $0 == .deleted }
    )
    await #expect(throws: DesignDatabaseRuntimeError.revisionCollected(
      receipt.candidateRevision.revisionID.description
    )) {
      _ = try await attachment.snapshotDescriptor(
        at: receipt.candidateRevision,
        expectedDatabaseID: create.databaseID
      )
    }
    _ = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    #expect(
      try await attachment.snapshotLeaseCoordinator.observation()
        .deletionAdmissionCount == 0
    )

    switch try await attachment.sweepRevisionCollection(
      operation: operation,
      requestDigest: request.requestDigest,
      maximumPhysicalDeletionCount: 1
    ) {
    case .collected(let repeatedReceipt):
      #expect(
        repeatedReceipt.intentStateDigest
          == terminalReceipt.intentStateDigest
      )
      #expect(
        repeatedReceipt.completedReachabilityGeneration
          == terminalReceipt.completedReachabilityGeneration
      )
    case .sweeping, .outcomeUnknown:
      Issue.record("A terminal collection retry did not return its receipt.")
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Collection admission rejects a candidate without an exact physical reclaimer")
  func collectionAdmissionRejectsMissingPhysicalReclaimer() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment(
      physicalWriteReclaimers: []
    )
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "collection-missing-reclaimer-create",
      genesisLow: 48
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "collection-missing-reclaimer-candidate",
      payload: Array("unreclaimable-write".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let receipt: DesignCommitReceipt
    switch try await attachment.submit(
      submission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("The missing-reclaimer candidate was rejected: \(rejection)")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The missing-reclaimer candidate outcome was unknown.")
      _ = await attachment.close()
      return
    }
    let operation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collection-missing-reclaimer-delete"
      )
    )
    let request = try DesignDatabaseRuntimeCollectionAdmissionRequest(
      operation: operation,
      candidates: try DesignDatabaseRuntimeRevisionDeletionCandidateSet(
        revisions: [receipt.candidateRevision]
      ),
      using: SHA256ContentDigester()
    )
    await #expect(throws: DesignDatabaseRuntimeError
      .physicalWriteReclaimerUnavailable(
        storageType: "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1"
      )) {
      _ = try await attachment.admitRevisionCollection(request)
    }
    _ = try await attachment.snapshotDescriptor(
      at: receipt.candidateRevision,
      expectedDatabaseID: create.databaseID
    )
    let context = try await attachment.context()
    let persisted = try await context.withTransaction { transaction in
      let intent = try await transaction.fetch(
        DesignCollectionIntentModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let lifecycle = try await transaction.fetch(
        DesignRevisionLifecycleModel.self,
        identifiedBy: receipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      return (intent, lifecycle)
    }
    #expect(persisted.0 == nil)
    #expect(
      try DesignDatabaseRuntimeRevisionLifecycle.validate(
        try #require(persisted.1),
        revision: receipt.candidateRevision,
        using: SHA256ContentDigester()
      ) == .visible
    )
    #expect(await attachment.close() == .closed)
  }

  @Test("Decoded projection page cache preserves leases during eviction and close")
  func decodedProjectionPageCacheLeaseAwareEviction() throws {
    let firstMaterialization = try DesignProjectionTreeBuilder().build(
      family: .entity,
      entries: [
        DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [1]),
          value: [11]
        ),
      ],
      digester: SHA256ContentDigester()
    )
    let secondMaterialization = try DesignProjectionTreeBuilder().build(
      family: .entity,
      entries: [
        DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [2]),
          value: [22]
        ),
      ],
      digester: SHA256ContentDigester()
    )
    let firstNode = try #require(
      firstMaterialization.nodes.first {
        $0.digest == firstMaterialization.reference.rootNodeDigest
      }
    )
    let secondNode = try #require(
      secondMaterialization.nodes.first {
        $0.digest == secondMaterialization.reference.rootNodeDigest
      }
    )
    let firstPage = try DesignProjectionDecodedPage(node: firstNode)
    let secondPage = try DesignProjectionDecodedPage(node: secondNode)
    let cache = DesignProjectionDecodedPageCache(
      policy: try DesignProjectionDecodedPageCachePolicy(
        shardCount: 1,
        maximumEntryCount: 1,
        maximumAccountedResidentByteCount: max(
          firstPage.accountedResidentByteCount,
          secondPage.accountedResidentByteCount
        )
      )
    )
    let firstKey = DesignProjectionDecodedPageKey(
      family: .entity,
      reference: firstMaterialization.reference,
      nodeDigest: firstNode.digest
    )
    let secondKey = DesignProjectionDecodedPageKey(
      family: .entity,
      reference: secondMaterialization.reference,
      nodeDigest: secondNode.digest
    )
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try cache.insertAndBorrow(firstPage, for: secondKey)
    }

    let firstLease = try cache.insertAndBorrow(firstPage, for: firstKey)
    let uncachedSecondLease = try cache.insertAndBorrow(
      secondPage,
      for: secondKey
    )
    var metrics = cache.metrics()
    #expect(metrics.residentEntryCount == 1)
    #expect(metrics.insertionCount == 1)
    #expect(metrics.evictionCount == 0)
    #expect(firstLease.entry(at: 0).value == [11])
    #expect(uncachedSecondLease.entry(at: 0).value == [22])
    uncachedSecondLease.close()
    firstLease.close()

    let retainedSecondLease = try cache.insertAndBorrow(
      secondPage,
      for: secondKey
    )
    metrics = cache.metrics()
    #expect(metrics.residentEntryCount == 1)
    #expect(metrics.insertionCount == 2)
    #expect(metrics.evictionCount == 1)
    #expect(try cache.borrow(firstKey) == nil)
    let hitLease = try #require(try cache.borrow(secondKey))
    #expect(hitLease.entry(at: 0).value == [22])
    hitLease.close()

    cache.close()
    #expect(retainedSecondLease.entry(at: 0).value == [22])
    #expect(cache.metrics().residentEntryCount == 0)
    retainedSecondLease.close()
    #expect(cache.metrics().activeLeaseCount == 0)
  }

  @Test("Decoded projection page cache serializes concurrent borrow and close")
  func decodedProjectionPageCacheConcurrentBorrowAndClose() async throws {
    let materialization = try DesignProjectionTreeBuilder().build(
      family: .entity,
      entries: [
        DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [7]),
          value: [77]
        ),
      ],
      digester: SHA256ContentDigester()
    )
    let node = try #require(
      materialization.nodes.first {
        $0.digest == materialization.reference.rootNodeDigest
      }
    )
    let page = try DesignProjectionDecodedPage(node: node)
    let cache = DesignProjectionDecodedPageCache(
      policy: try DesignProjectionDecodedPageCachePolicy(
        shardCount: 1,
        maximumEntryCount: 1,
        maximumAccountedResidentByteCount: page.accountedResidentByteCount
      )
    )
    let key = DesignProjectionDecodedPageKey(
      family: .entity,
      reference: materialization.reference,
      nodeDigest: node.digest
    )
    try cache.insertAndBorrow(page, for: key).close()

    let successfulBorrowCount = try await withThrowingTaskGroup(
      of: Int.self,
      returning: Int.self
    ) { group in
      for _ in 0..<64 {
        group.addTask {
          guard let lease = try cache.borrow(key) else { return 0 }
          defer { lease.close() }
          return lease.entry(at: 0).value == [77] ? 1 : 0
        }
      }
      var count = 0
      for try await result in group {
        count += result
      }
      return count
    }
    #expect(successfulBorrowCount == 64)
    #expect(cache.metrics().activeLeaseCount == 0)

    var retainedLeases: [DesignProjectionDecodedPageLease] = []
    retainedLeases.reserveCapacity(32)
    for _ in 0..<32 {
      retainedLeases.append(try #require(try cache.borrow(key)))
    }
    await withTaskGroup(of: Void.self) { group in
      for lease in retainedLeases {
        group.addTask {
          lease.close()
        }
      }
      group.addTask {
        cache.close()
      }
    }
    #expect(cache.metrics().activeLeaseCount == 0)
    #expect(cache.metrics().residentEntryCount == 0)
  }

  @Test("Projection packing preserves semantics and rejects tampered node payload")
  func projectionPackingAndTamperDetection() throws {
    let entries = try (0..<4_097).reversed().map { index in
      let value = UInt32(index)
      return try DesignProjectionEntry(
        key: DesignCanonicalKey(bytes: [
          UInt8(truncatingIfNeeded: value >> 24),
          UInt8(truncatingIfNeeded: value >> 16),
          UInt8(truncatingIfNeeded: value >> 8),
          UInt8(truncatingIfNeeded: value),
        ]),
        value: [UInt8(truncatingIfNeeded: value)]
      )
    }
    let digester = SHA256ContentDigester()
    let canonical = try DesignProjectionTreeBuilder().build(
      family: .facet,
      entries: entries,
      digester: digester
    )
    let alternateProfile = DesignProjectionPhysicalProfile(
      codecVersion: DesignProjectionPhysicalCodecVersion(major: 2, minor: 0),
      maximumLeafEntryCount: 48,
      minimumLeafEntryCount: 24,
      maximumInternalChildCount: 48,
      minimumInternalChildCount: 24,
      maximumNodePayloadByteCount: 49_152
    )
    let repacked = try DesignProjectionTreeBuilder().build(
      family: .facet,
      entries: entries,
      profile: alternateProfile,
      digester: digester
    )

    #expect(canonical.rootLevel >= 2)
    #expect(canonical.descriptor == repacked.descriptor)
    #expect(canonical.descriptorDigest == repacked.descriptorDigest)
    #expect(canonical.reference.physicalProfileDigest != repacked.reference.physicalProfileDigest)
    #expect(canonical.reference.rootNodeDigest != repacked.reference.rootNodeDigest)

    let removed = try canonical.semanticAccumulator.removing(
      entries[2_048],
      family: .facet,
      semanticVersion: canonical.descriptor.semanticVersion,
      using: digester
    )
    let restored = try removed.adding(
      entries[2_048],
      family: .facet,
      semanticVersion: canonical.descriptor.semanticVersion,
      using: digester
    )
    #expect(restored == canonical.semanticAccumulator)
    #expect(
      try restored.sequenceDigest(
        family: .facet,
        semanticVersion: canonical.descriptor.semanticVersion,
        entryCount: canonical.descriptor.entryCount,
        using: digester
      ) == canonical.descriptor.canonicalSequenceDigest
    )

    let databaseID = try DesignDatabaseID(high: 900, low: 901)
    let revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 902)
    )
    let persisted = try canonical.models(
      databaseID: databaseID,
      revision: revision
    )
    var tampered = try #require(persisted.nodes.first)
    let expectedNode = try #require(canonical.nodes.first { node in
      DesignProjectionTreeMaterialization.digestKey(node.digest) == tampered.id
    })
    tampered.payload = ByteString(Array(tampered.payload) + [0])
    tampered.encodedByteCount = String(Array(tampered.payload).count)
    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignProjectionPersistedNodeDecoder.decode(
        tampered,
        expectedDigest: expectedNode.digest,
        family: .facet,
        reference: canonical.reference,
        digester: digester
      )
    }
  }

  @Test("Persisted semantic accumulator tamper is rejected during directory load")
  func persistedSemanticAccumulatorTamperIsRejected() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: []
    )
    let locator = try DesignDatabaseLocator(
      namespace: "runtime-test",
      segments: ["projection-accumulator-tamper"]
    )
    let container = try await DisabledTestContainerProvider().openContainer(
      for: locator,
      registration: registration
    )
    let context = container.newContext()
    let databaseID = try DesignDatabaseID(high: 910, low: 911)
    let revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 912)
    )
    let materialization = try DesignProjectionTreeBuilder().build(
      family: .entity,
      entries: [
        DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: [1]),
          value: [2]
        ),
      ],
      digester: SHA256ContentDigester()
    )
    let models = try materialization.models(
      databaseID: databaseID,
      revision: revision
    )
    var mutableDescriptor = models.descriptor
    let firstByte = mutableDescriptor.accumulatorFirst.first
    mutableDescriptor.accumulatorFirst = String(
      firstByte == "0" ? "1" : "0"
    ) + mutableDescriptor.accumulatorFirst.dropFirst()
    let tamperedDescriptor = mutableDescriptor

    try await context.withTransaction { transaction in
      try await transaction.save(tamperedDescriptor, precondition: .notExists)
      try await transaction.save(models.binding, precondition: .notExists)
      try await transaction.save(models.materialization, precondition: .notExists)
      for node in models.nodes {
        try await transaction.save(node, precondition: .notExists)
      }
    }
    let encodedDirectory = try DesignDatabaseRuntimeProjectionDirectory.encode([
      materialization,
    ])
    var rejected = false
    do {
      _ = try await context.withTransaction { transaction in
        try await DesignDatabaseRuntimeProjectionDirectory.load(
          revision: revision,
          databaseID: databaseID,
          count: 1,
          encoded: encodedDirectory,
          transaction: transaction,
          digester: SHA256ContentDigester()
        )
      }
      Issue.record("A tampered persisted semantic accumulator was accepted.")
    } catch let error as DesignDatabaseRuntimeError {
      switch error {
      case .persistedStateCorrupt(let reason):
        rejected = true
        #expect(reason.contains("digest does not match"))
      default:
        Issue.record("Accumulator tamper used the wrong typed failure: \(error)")
      }
    } catch {
      Issue.record("Accumulator tamper escaped as an untyped failure: \(error)")
    }
    #expect(rejected)
    await container.shutdown()
  }

  @Test("Single existing-family update persists only the immutable root path")
  func existingFamilyUpdateSharesUnchangedNodes() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: []
    )
    let locator = try DesignDatabaseLocator(
      namespace: "runtime-test",
      segments: ["projection-path-sharing"]
    )
    let container = try await DisabledTestContainerProvider().openContainer(
      for: locator,
      registration: registration
    )
    let context = container.newContext()
    let entries = try (0..<4_097).map { index in
      let value = UInt32(index)
      return try DesignProjectionEntry(
        key: DesignCanonicalKey(bytes: [
          UInt8(truncatingIfNeeded: value >> 24),
          UInt8(truncatingIfNeeded: value >> 16),
          UInt8(truncatingIfNeeded: value >> 8),
          UInt8(truncatingIfNeeded: value),
        ]),
        value: [UInt8(truncatingIfNeeded: value)]
      )
    }
    let digester = SHA256ContentDigester()
    let base = try DesignProjectionTreeBuilder().build(
      family: .facet,
      entries: entries,
      digester: digester
    )
    let databaseID = try DesignDatabaseID(high: 920, low: 921)
    let revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 922)
    )
    let persisted = try base.models(
      databaseID: databaseID,
      revision: revision
    )
    try await context.withTransaction { transaction in
      for node in persisted.nodes {
        try await transaction.save(node, precondition: .notExists)
      }
    }

    let before = entries[2_048]
    let after = try DesignProjectionEntry(
      key: before.key,
      value: [0xaa, 0x55]
    )
    let reads = DesignDatabaseRuntimeReadSnapshot(
      context: context,
      revision: revision,
      maximumReadCount: 16
    )
    let outcome = try await DesignProjectionTreeUpdater().update(
      base: DesignProjectionRuntimeMaterialization(
        descriptor: base.descriptor,
        descriptorDigest: base.descriptorDigest,
        semanticAccumulator: base.semanticAccumulator,
        reference: base.reference,
        rootLevel: base.rootLevel,
        totalNodeCount: base.totalNodeCount
      ),
      changes: [
        DesignProjectionChange(
          family: .facet,
          before: before,
          after: after
        ),
      ],
      reads: reads,
      digester: digester
    )
    await reads.close()
    switch outcome {
    case .updated(let updated):
      #expect(updated.totalNodeCount == base.totalNodeCount)
      #expect(updated.rootLevel == base.rootLevel)
      #expect(updated.nodes.count == Int(base.rootLevel) + 1)
      #expect(UInt64(updated.nodes.count) < updated.totalNodeCount)
      #expect(updated.reference.rootNodeDigest != base.reference.rootNodeDigest)
      #expect(updated.descriptorDigest != base.descriptorDigest)
    case .rejected(let reason):
      Issue.record("A valid single path-copy update was rejected: \(reason)")
    case .budgetExceeded(let limit, let requested):
      Issue.record(
        "A single path-copy update exceeded its read budget: \(requested)/\(limit)"
      )
    }
    await container.shutdown()
  }

  @Test("Registration is deterministic and validates the framework schema")
  func deterministicRegistration() throws {
    let logic = try contribution(
      id: "lsi.logic",
      digestByte: "1",
      entity: RuntimeTestLogicEntity.self
    )
    let layout = try contribution(
      id: "lsi.layout",
      digestByte: "2",
      entity: RuntimeTestLayoutEntity.self
    )
    let builder = DesignDatabaseRuntimeRegistrationBuilder()
    let first = try builder.build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [logic, layout]
    )
    let second = try builder.build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [layout, logic]
    )

    #expect(first.contributionIDs == first.contributionIDs.sorted())
    #expect(first.contributionIDs.contains(logic.id))
    #expect(first.contributionIDs.contains(layout.id))
    #expect(first.contributionIDs.count == 3)
    #expect(first.schemaFingerprint == second.schemaFingerprint)
    #expect(first.designSchemaBundle == second.designSchemaBundle)
    #expect(first.designSchemaBundle.members.count == 2)
    #expect(first.registrationDigest == second.registrationDigest)
    #expect(first.schema.entities.map(\.name) == second.schema.entities.map(\.name))
  }

  @Test("Duplicate contribution identity is rejected before container open")
  func duplicateContributionRejected() throws {
    let contribution = try self.contribution(
      id: "lsi.logic",
      digestByte: "1",
      entity: RuntimeTestLogicEntity.self
    )

    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimeRegistrationBuilder().build(
        schemaVersion: Schema.Version(1, 0, 0),
        contributions: [contribution, contribution]
      )
    }
  }

  @Test("Duplicate semantic schema identity is rejected before container open")
  func duplicateDesignSchemaRejected() throws {
    let logic = try contribution(
      id: "lsi.logic-runtime",
      schemaID: "lsi.shared-schema",
      digestByte: "1",
      entity: RuntimeTestLogicEntity.self
    )
    let layout = try contribution(
      id: "lsi.layout-runtime",
      schemaID: "lsi.shared-schema",
      digestByte: "2",
      entity: RuntimeTestLayoutEntity.self
    )

    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimeRegistrationBuilder().build(
        schemaVersion: Schema.Version(1, 0, 0),
        contributions: [logic, layout]
      )
    }
  }

  @Test("Contribution rejects a schema and runtime entity mismatch")
  func contributionMismatchRejected() throws {
    let id = try DesignDatabaseRuntimeContributionID("lsi.logic")
    let bindingDigest = try digest(repeating: "1")
    let logicSchema = try RuntimeTestLogicEntity.schemaEntity
    let layoutRuntime = try DatabaseFrameworkRuntime.entity(RuntimeTestLayoutEntity.self)

    #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try DesignDatabaseRuntimeContribution(
        id: id,
        designSchemaMember: DesignSchemaBundleMember(
          schemaID: DesignSchemaID(rawValue: "lsi.logic"),
          version: .v1,
          canonicalDigest: bindingDigest
        ),
        bindingDigest: bindingDigest,
        entities: [logicSchema],
        entityRuntimes: [layoutRuntime]
      )
    }
  }

  @Test("Valid host container attaches and closes exactly once")
  func validContainerAttachment() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["runtime-test"]
    )
    let attachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: DisabledTestContainerProvider()
    ).open(locator: locator, registration: registration)

    #expect(attachment.locator == locator)
    #expect(attachment.schemaFingerprint == registration.schemaFingerprint)
    #expect(attachment.registrationDigest == registration.registrationDigest)
    #expect(await attachment.close() == .closed)
    #expect(await attachment.close() == .alreadyClosed)
  }

  @Test("A host container opened with another schema is rejected")
  func mismatchedContainerRejected() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["runtime-test"]
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await DesignDatabaseRuntimeAttacher(
        containerProvider: MismatchingContainerProvider()
      ).open(locator: locator, registration: registration)
    }
  }

  @Test("Genesis publication is atomic, replayable, and status-visible")
  func genesisPublicationAndReplay() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let request = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-1",
      genesisLow: 10
    )

    let first = try await attachment.createGenesis(request)
    let firstResult: DesignDatabaseRuntimeCreationResult
    switch first {
    case .created(let result):
      firstResult = result
      #expect(!result.wasReplayed)
      #expect(result.genesisRevision.revisionID == request.genesisRevisionID)
    case .outcomeUnknown:
      Issue.record("In-memory SQLite returned an unknown genesis outcome.")
      _ = await attachment.close()
      return
    }

    let status = try await attachment.creationStatus(
      operation: firstResult.operation,
      requestDigest: request.requestDigest
    )
    switch status {
    case .created(let result):
      #expect(result.wasReplayed)
      #expect(result.outcomeDigest == firstResult.outcomeDigest)
    case .notRecorded:
      Issue.record("Committed creation receipt was not visible.")
    }

    let replay = try await attachment.createGenesis(request)
    switch replay {
    case .created(let result):
      #expect(result.wasReplayed)
      #expect(result.outcomeDigest == firstResult.outcomeDigest)
    case .outcomeUnknown:
      Issue.record("An exact creation replay returned an unknown outcome.")
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("A reused scoped creation operation with another request is rejected")
  func creationIdempotencyConflict() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let first = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-1",
      genesisLow: 10
    )
    _ = try await attachment.createGenesis(first)
    let conflicting = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-1",
      genesisLow: 11
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.createGenesis(conflicting)
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("A second creation operation cannot replace an existing catalog")
  func existingCatalogRejected() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let first = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-1",
      genesisLow: 10
    )
    _ = try await attachment.createGenesis(first)
    let second = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-2",
      genesisLow: 10
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.createGenesis(second)
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Genesis request cannot cross an attachment registration boundary")
  func genesisRegistrationMismatchRejected() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let request = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: digest(repeating: "f"),
      operation: "create-1",
      genesisLow: 10
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.createGenesis(request)
    }
    let operation = DesignDatabaseOperationReference(
      databaseID: request.databaseID,
      authorizationSubjectScopeID: request.authorizationSubjectScopeID,
      operationID: request.operationID
    )
    #expect(
      try await attachment.creationStatus(
        operation: operation,
        requestDigest: request.requestDigest
      ) == .notRecorded
    )
    #expect(await attachment.close() == .closed)
  }

  @Test("A matching root digest cannot substitute another schema member set")
  func genesisSchemaMembersMismatchRejected() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let spoofedBundle = try DesignSchemaBundle(
      members: [],
      rootDigest: registration.designSchemaBundle.rootDigest
    )
    let request = try genesisRequest(
      locator: locator,
      designSchemaBundle: spoofedBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-spoofed-schema",
      genesisLow: 10
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.createGenesis(request)
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Open inspection validates identity, registration, reference, and capabilities")
  func databaseInspection() async throws {
    let (attachment, registration, locator) = try await makeAttachment()
    let capabilities = try capabilitySet(id: "query.keyset")
    let request = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "create-1",
      genesisLow: 10,
      capabilities: capabilities
    )
    _ = try await attachment.createGenesis(request)

    let descriptor = try await attachment.inspectDatabase(
      expectedDatabaseID: request.databaseID,
      requiredFeatureCapabilities: capabilities
    )
    #expect(descriptor.databaseID == request.databaseID)
    #expect(descriptor.genesisRevision.revisionID == request.genesisRevisionID)
    #expect(descriptor.mainRevision == descriptor.genesisRevision)
    #expect(descriptor.mainGeneration == 1)
    #expect(descriptor.featureCapabilities == capabilities)
    #expect(descriptor.schemaBundle == registration.designSchemaBundle)
    #expect(descriptor.registrationDigest == registration.registrationDigest)
    let context = try await attachment.context()
    let genesisLifecycle = try await context.withTransaction { transaction in
      try await transaction.fetch(
        DesignRevisionLifecycleModel.self,
        identifiedBy: request.genesisRevisionID.description,
        consistency: .serializable
      )
    }
    #expect(
      try DesignDatabaseRuntimeRevisionLifecycle.requireVisible(
        genesisLifecycle,
        revision: descriptor.genesisRevision,
        using: SHA256ContentDigester()
      ) == .visible
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.inspectDatabase(
        expectedDatabaseID: DesignDatabaseID(high: 9, low: 9),
        requiredFeatureCapabilities: capabilities
      )
    }
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.inspectDatabase(
        expectedDatabaseID: request.databaseID,
        requiredFeatureCapabilities: try capabilitySet(id: "query.missing")
      )
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Security-enabled production provider creates an exact typed handle")
  func productionProviderCreate() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["provider-create"]
    )
    let databaseID = try DesignDatabaseID(high: 5, low: 6)
    let genesisRevisionID = DesignRevisionID(high: 0, low: 20)
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 7, low: 8)
    let operationID = try DesignDatabaseOperationID(rawValue: "provider-create-1")
    let capabilities = try capabilitySet(id: "query.keyset")
    let schemaBundle = registration.designSchemaBundle
    let canonical = try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: operationID,
      declaredFeatureCapabilities: capabilities,
      initialSchemaBundle: schemaBundle,
      registrationDigest: registration.registrationDigest
    )
    let request = DesignDatabaseCreateRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      operationID: operationID,
      initialSchemaBundle: schemaBundle,
      declaredFeatureCapabilities: capabilities,
      requestDigest: canonical.requestDigest
    )
    let grants = DesignDatabaseAuthorizationGrantSet([.read, .proposeCandidate])
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: SecurityEnabledContainerProvider(),
      authorizationSubjectScopeID: subjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: StorageRoleRejectingRuntimeTestAuthorizer()
    )

    let handle = try await provider.create(request)
    #expect(handle.databaseID == databaseID)
    #expect(handle.authorizationSubjectScopeID == subjectScopeID)
    #expect(handle.authorizationGrants == grants)
    #expect(handle.featureCapabilities == capabilities)
    #expect(handle.genesisRevision.revisionID == genesisRevisionID)
    #expect(
      try await handle.resolve(.named(.main)) == handle.genesisRevision
    )
    let snapshot = try await handle.openSnapshot(at: handle.genesisRevision)
    #expect(snapshot.revision == handle.genesisRevision)
    #expect(snapshot.parents.isEmpty)
    #expect(snapshot.stateDigest.algorithm == .sha256)
    #expect(snapshot.designSchemaBundleDigest == registration.designSchemaBundleDigest)
    #expect(snapshot.dependencyRootDigest.algorithm == .sha256)
    #expect(snapshot.semanticDependencyGraphDigest.algorithm == .sha256)
    #expect(snapshot.directChangeRootDigest.algorithm == .sha256)
    #expect(await handle.close() == .closed)
    #expect(await snapshot.close() == .alreadyClosed)
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.openSnapshot(at: handle.genesisRevision)
    }
    #expect(await provider.close() == .closed)
  }

  @Test("Production provider rejects a host that omits the runtime storage role")
  func productionProviderRejectsMissingRuntimeStorageRole() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["provider-security-rejection"]
    )
    let databaseID = try DesignDatabaseID(high: 51, low: 52)
    let genesisRevisionID = DesignRevisionID(high: 0, low: 53)
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 54, low: 55)
    let operationID = try DesignDatabaseOperationID(
      rawValue: "provider-security-rejection"
    )
    let capabilities = try DesignCapabilitySet([])
    let canonical = try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: operationID,
      declaredFeatureCapabilities: capabilities,
      initialSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest
    )
    let request = DesignDatabaseCreateRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      operationID: operationID,
      initialSchemaBundle: registration.designSchemaBundle,
      declaredFeatureCapabilities: capabilities,
      requestDigest: canonical.requestDigest
    )
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: MissingRuntimeStorageRoleContainerProvider(),
      authorizationSubjectScopeID: subjectScopeID,
      creationRequestedAuthorization: DesignDatabaseAuthorizationGrantSet([.read]),
      authorizer: AllowingRuntimeTestAuthorizer()
    )

    do {
      let handle = try await provider.create(request)
      _ = await handle.close()
      Issue.record("A host without the runtime storage role created a database.")
    } catch {
      guard case .persistence(let reason) = error else {
        Issue.record("The security rejection was not returned as a typed persistence failure.")
        _ = await provider.close()
        return
      }
      #expect(reason.localizedCaseInsensitiveContains("authorization"))
    }
    #expect(await provider.close() == .closed)
  }

  @Test("Reference CAS is exact, replayable, tombstoned, and status-visible")
  func productionReferenceCAS() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["provider-reference"]
    )
    let databaseID = try DesignDatabaseID(high: 15, low: 16)
    let genesisRevisionID = DesignRevisionID(high: 0, low: 30)
    let genesis = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: genesisRevisionID
    )
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 17, low: 18)
    let createOperationID = try DesignDatabaseOperationID(
      rawValue: "provider-reference-create"
    )
    let capabilities = try DesignCapabilitySet([])
    let canonicalCreate = try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: createOperationID,
      declaredFeatureCapabilities: capabilities,
      initialSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .promoteReference,
      .inspectOwnOperationOutcome,
    ])
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: SecurityEnabledContainerProvider(),
      authorizationSubjectScopeID: subjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let handle = try await provider.create(
      DesignDatabaseCreateRequest(
        locator: locator,
        databaseID: databaseID,
        genesisRevisionID: genesisRevisionID,
        operationID: createOperationID,
        initialSchemaBundle: registration.designSchemaBundle,
        declaredFeatureCapabilities: capabilities,
        requestDigest: canonicalCreate.requestDigest
      )
    )
    let candidate = try DesignReferenceName(rawValue: "candidate")

    let createCandidate = try referenceRequest(
      operation: "reference-create",
      name: candidate,
      expectedGeneration: 0,
      expectedRevision: nil,
      desiredRevision: genesis
    )
    let first = try await handle.compareAndSetReference(createCandidate)
    let receipt: DesignReferenceUpdateReceipt
    switch first {
    case .applied(let applied):
      receipt = applied
      #expect(applied.generation == 1)
      #expect(applied.previousRevision == nil)
      #expect(applied.currentRevision == genesis)
    case .rejected(let rejection):
      Issue.record("Exact candidate reference creation was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("In-memory reference creation returned an unknown outcome.")
      return
    }
    #expect(try await handle.resolve(.named(candidate)) == genesis)
    #expect(try await handle.compareAndSetReference(createCandidate) == first)
    let status = try await handle.referenceStatus(
      operation: receipt.operation,
      requestDigest: createCandidate.requestDigest
    )
    #expect(status == .applied(receipt))

    let stale = try referenceRequest(
      operation: "reference-stale",
      name: candidate,
      expectedGeneration: 0,
      expectedRevision: nil,
      desiredRevision: genesis
    )
    switch try await handle.compareAndSetReference(stale) {
    case .rejected(let rejection):
      #expect(
        rejection.reason == .preconditionMismatch(
          actualGeneration: 1,
          actualRevision: genesis
        )
      )
    default:
      Issue.record("A stale reference precondition was not rejected.")
    }

    let delete = try referenceRequest(
      operation: "reference-delete",
      name: candidate,
      expectedGeneration: 1,
      expectedRevision: genesis,
      desiredRevision: nil
    )
    switch try await handle.compareAndSetReference(delete) {
    case .applied(let deleted):
      #expect(deleted.generation == 2)
      #expect(deleted.currentRevision == nil)
    default:
      Issue.record("Exact reference deletion was not applied.")
    }
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.resolve(.named(candidate))
    }

    let recreate = try referenceRequest(
      operation: "reference-recreate",
      name: candidate,
      expectedGeneration: 2,
      expectedRevision: nil,
      desiredRevision: genesis
    )
    switch try await handle.compareAndSetReference(recreate) {
    case .applied(let recreated):
      #expect(recreated.generation == 3)
    default:
      Issue.record("A tombstoned reference was not recreated by exact generation.")
    }
    let conflictingReplay = try referenceRequest(
      operation: "reference-recreate",
      name: candidate,
      expectedGeneration: 3,
      expectedRevision: genesis,
      desiredRevision: nil
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.compareAndSetReference(conflictingReplay)
    }
    #expect(await handle.close() == .closed)
    #expect(await provider.close() == .closed)
  }

  @Test("Materialization interruption resumes without repeating validation")
  func preIntentMaterializationInterruptionResume() async throws {
    let counter = RuntimeTestPreparationCounter()
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestPreIntentMutationAdapter(
            counter: counter,
            failureGate: RuntimeTestMaterializationFailureGate()
          )
        ),
      ]
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-pre-intent-resume-" + UUID().uuidString,
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      do {
        try FileManager.default.removeItem(at: temporaryDirectory)
      } catch {
        Issue.record(
          "The pre-intent resume test could not remove its temporary database: \(error)"
        )
      }
    }
    let provider = ReopenableSQLiteContainerProvider(
      databasePath: temporaryDirectory
        .appendingPathComponent("design.sqlite")
        .path(percentEncoded: false)
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["pre-intent-resume"]
    )
    let firstAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "pre-intent-create",
      genesisLow: 709
    )
    _ = try await firstAttachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await firstAttachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "pre-intent-candidate",
      payload: Array("validated-once".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: submission.operationID
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await firstAttachment.submit(
        submission,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      )
    }
    #expect(
      try await firstAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )
    let firstContext = try await firstAttachment.context()
    let persisted = try await firstContext.withTransaction { transaction in
      let key = DesignDatabaseRuntimeOperationClaim.key(operation)
      let claim = try await transaction.fetch(
        DesignOperationClaimModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let reservation = try await transaction.fetch(
        DesignIdentityReservationModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let validation = try await transaction.fetch(
        DesignValidatedMutationDirectoryModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let prepared = try await transaction.fetch(
        DesignPreparedMutationDirectoryModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      return (claim, reservation, validation, intent, prepared)
    }
    #expect(persisted.0 != nil)
    #expect(persisted.1 != nil)
    #expect(persisted.2 != nil)
    #expect(persisted.3 == nil)
    #expect(persisted.4 == nil)
    #expect(await firstAttachment.close() == .closed)

    let resumedAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    #expect(
      try await resumedAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )
    switch try await resumedAttachment.submit(
      submission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed:
      break
    case .rejected(let rejection):
      Issue.record("Pre-intent resume was rejected: \(rejection)")
    case .outcomeUnknown:
      Issue.record("Pre-intent resume returned an unknown outcome.")
    }
    let counts = counter.counts()
    #expect(counts.validation == 1)
    #expect(counts.materialization == 2)
    #expect(await resumedAttachment.close() == .closed)
  }

  @Test("Physical collection claim fences only while claimed and permits deleted identity reuse")
  func physicalCollectionClaimFencesMatchingStagedWrite() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "physical-claim-create",
      genesisLow: 711
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let blockedSubmission = try mutationSubmission(
      operation: "physical-claim-blocked-candidate",
      payload: Array("blocked".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let blockedOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: blockedSubmission.operationID
    )
    let blockedRevisionID = try DesignRevisionID(
      hexadecimalValue: String(
        blockedSubmission.requestDigest.hexadecimalValue.prefix(32)
      )
    )
    let blockedIdentity = try DesignDatabaseRuntimeImmutableWriteIdentity(
      storageType: "DesignDatabaseRuntimeTests.RuntimeTestLogicEntity.v1",
      modelID: blockedRevisionID.description
    )
    let claim = try DesignDatabaseRuntimePhysicalCollectionClaim.makeClaimed(
      identity: blockedIdentity,
      collectionIntentID: "collection:physical-claim-fence",
      using: SHA256ContentDigester()
    )
    let context = try await attachment.context()
    try await context.withTransaction { transaction in
      try await transaction.save(claim, precondition: .notExists)
    }

    await #expect(throws: DesignDatabaseRuntimeError.physicalWriteDeleting(
      identity: claim.id,
      collectionOperation: claim.collectionIntentID
    )) {
      _ = try await attachment.submit(
        blockedSubmission,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      )
    }
    #expect(
      try await attachment.commitStatus(
        operation: blockedOperation,
        requestDigest: blockedSubmission.requestDigest
      ) == .inProgress
    )
    let blockedState = try await context.withTransaction { transaction in
      let key = DesignDatabaseRuntimeOperationClaim.key(blockedOperation)
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let stagingRoot = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let reachability = try await DesignDatabaseRuntimeReachability.require(
        databaseID: create.databaseID,
        transaction: transaction
      )
      let stagedModel = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: blockedRevisionID.description,
        consistency: .serializable
      )
      return (intent, stagingRoot, reachability, stagedModel)
    }
    let blockedIntent = try #require(blockedState.0)
    let blockedStagingRoot = try #require(blockedState.1)
    #expect(blockedIntent.stagedDomainWriteCount == 0)
    #expect(blockedIntent.stagedProjectionNodeCount == 0)
    #expect(
      blockedState.2.generation == blockedStagingRoot.reachabilityGeneration
    )
    #expect(blockedState.3 == nil)

    let unrelatedSubmission = try mutationSubmission(
      operation: "physical-claim-unrelated-candidate",
      payload: Array("unrelated".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let unrelatedReceipt: DesignCommitReceipt
    switch try await attachment.submit(
      unrelatedSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let receipt):
      unrelatedReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The unrelated candidate was rejected: \(rejection)")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The unrelated candidate returned an unknown outcome.")
      _ = await attachment.close()
      return
    }
    let unrelatedModel = try await context.withTransaction { transaction in
      try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: unrelatedReceipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
    }
    #expect(unrelatedModel?.name == "unrelated")

    let deletedClaim = try DesignDatabaseRuntimePhysicalCollectionClaim
      .transitionedDeleted(
        claim,
        expectedIdentity: blockedIdentity,
        collectionIntentID: claim.collectionIntentID,
        using: SHA256ContentDigester()
      )
    try await context.withTransaction { transaction in
      try await transaction.save(deletedClaim, precondition: .exists)
    }
    switch try await attachment.submit(
      blockedSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let receipt):
      #expect(receipt.candidateRevision.revisionID == blockedRevisionID)
    case .rejected(let rejection):
      Issue.record("The deleted physical identity was not reusable: \(rejection)")
    case .outcomeUnknown:
      Issue.record("The deleted physical identity reuse outcome was unknown.")
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Partial commit staging resumes after a persistent container reopen")
  func persistentCommitStagingResume() async throws {
    let stagingLimit = DesignDatabaseRuntimeCommitBuildIntent
      .stagingTransactionWriteLimit
    let writeCount = stagingLimit * 2 + 2
    let failureGate = RuntimeTestStagingFailureGate(
      failureIndex: stagingLimit
    )
    let preparationCounter = RuntimeTestPreparationCounter()
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestResumableMutationAdapter(
            writeCount: writeCount,
            failureGate: failureGate,
            preparationCounter: preparationCounter
          )
        ),
      ]
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-staging-resume-" + UUID().uuidString,
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      do {
        try FileManager.default.removeItem(at: temporaryDirectory)
      } catch {
        Issue.record(
          "The persistent staging test could not remove its temporary database: \(error)"
        )
      }
    }
    let provider = ReopenableSQLiteContainerProvider(
      databasePath: temporaryDirectory
        .appendingPathComponent("design.sqlite")
        .path(percentEncoded: false)
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["persistent-staging-resume"]
    )
    let firstAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let genesisRequest = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "persistent-staging-create",
      genesisLow: 710
    )
    _ = try await firstAttachment.createGenesis(genesisRequest)
    let genesis = DesignRevisionReference(
      databaseID: genesisRequest.databaseID,
      revisionID: genesisRequest.genesisRevisionID
    )
    let base = try await firstAttachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: genesisRequest.databaseID
    )
    let submission = try mutationSubmission(
      operation: "persistent-staging-candidate",
      payload: Array("resumable".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest,
      expectedWriteCount: writeCount
    )
    let operation = DesignDatabaseOperationReference(
      databaseID: genesisRequest.databaseID,
      authorizationSubjectScopeID: genesisRequest.authorizationSubjectScopeID,
      operationID: submission.operationID
    )

    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await firstAttachment.submit(
        submission,
        databaseID: genesisRequest.databaseID,
        authorizationSubjectScopeID: genesisRequest.authorizationSubjectScopeID
      )
    }
    #expect(
      try await firstAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )
    let firstContext = try await firstAttachment.context()
    let partialState = try await firstContext.withTransaction {
      transaction in
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let preparedDirectory = try await transaction.fetch(
        DesignPreparedMutationDirectoryModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let validatedDirectory = try await transaction.fetch(
        DesignValidatedMutationDirectoryModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let identityReservation = try await transaction.fetch(
        DesignIdentityReservationModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let submissionCapsule = try await transaction.fetch(
        DesignCommitSubmissionModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let stagingRoot = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let reachability = try await transaction.fetch(
        DesignReachabilityStateModel.self,
        identifiedBy: "active",
        consistency: .serializable
      )
      return (
        intent,
        preparedDirectory,
        validatedDirectory,
        identityReservation,
        submissionCapsule,
        stagingRoot,
        reachability
      )
    }
    let partialIntent = try #require(partialState.0)
    let preparedDirectory = try #require(partialState.1)
    let validatedDirectory = try #require(partialState.2)
    let identityReservation = try #require(partialState.3)
    let submissionCapsule = try #require(partialState.4)
    let activeStagingRoot = try #require(partialState.5)
    let partialReachability = try #require(partialState.6)
    #expect(partialIntent.state == DesignCommitBuildIntentState.staging.rawValue)
    #expect(partialIntent.stagedDomainWriteCount == stagingLimit)
    #expect(partialIntent.expectedDomainWriteCount == writeCount)
    #expect(partialIntent.stagedProjectionNodeCount == 0)
    #expect(partialIntent.expectedProjectionNodeCount > 0)
    #expect(preparedDirectory.recordCount == 1)
    #expect(!Array(preparedDirectory.payload).isEmpty)
    #expect(
      preparedDirectory.payloadDigestValue
        == partialIntent.preparedDirectoryDigestValue
    )
    #expect(validatedDirectory.recordCount == 1)
    #expect(!Array(validatedDirectory.payload).isEmpty)
    #expect(
      validatedDirectory.payloadDigestValue
        == identityReservation.validatedDirectoryDigestValue
    )
    #expect(
      validatedDirectory.recordCount
        == identityReservation.validatedMutationCount
    )
    #expect(
      activeStagingRoot.state
        == DesignDatabaseRuntimeStagingRootState.active.rawValue
    )
    #expect(activeStagingRoot.reachabilityGeneration == 2)
    #expect(partialReachability.generation == 2)
    let restoredSubmission = try DesignDatabaseRuntimeCommitSubmissionCapsule(
      model: submissionCapsule,
      operation: operation,
      expectedRequestDigest: submission.requestDigest,
      expectedPlanDigest: submission.plan.planDigest,
      using: SHA256ContentDigester()
    )
    #expect(restoredSubmission.submission == submission)
    let tamperedSubmissionCapsule: DesignCommitSubmissionModel = {
      var value = submissionCapsule
      value.payload = ByteString(Array(submissionCapsule.payload) + [0])
      return value
    }()
    try await firstContext.withTransaction { transaction in
      try await transaction.save(
        tamperedSubmissionCapsule,
        precondition: .exists
      )
    }
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await firstAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      )
    }
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      try await firstAttachment.validateCommitRecoveryBeforeServingOpens()
    }
    try await firstContext.withTransaction { transaction in
      try await transaction.save(submissionCapsule, precondition: .exists)
    }
    try await firstAttachment.validateCommitRecoveryBeforeServingOpens()
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      try await firstAttachment.validateCommitRecoveryBeforeServingOpens(
        maximumIntentCount: 0
      )
    }
    #expect(
      try await firstAttachment.persistedCommitSubmission(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == submission
    )
    let candidateRevision = DesignRevisionReference(
      databaseID: genesisRequest.databaseID,
      revisionID: try DesignRevisionID(
        hexadecimalValue: partialIntent.candidateRevisionID
      )
    )
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await firstAttachment.snapshotDescriptor(
        at: candidateRevision,
        expectedDatabaseID: genesisRequest.databaseID
      )
    }
    let tamperedValidatedDirectory: DesignValidatedMutationDirectoryModel = {
      var value = validatedDirectory
      value.payload = ByteString(Array(validatedDirectory.payload) + [0])
      return value
    }()
    try await firstContext.withTransaction { transaction in
      try await transaction.save(
        tamperedValidatedDirectory,
        precondition: .exists
      )
    }
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await firstAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      )
    }
    try await firstContext.withTransaction { transaction in
      try await transaction.save(validatedDirectory, precondition: .exists)
    }
    #expect(
      try await firstAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )
    let tamperedPreparedDirectory: DesignPreparedMutationDirectoryModel = {
      var value = preparedDirectory
      value.payload = ByteString(Array(preparedDirectory.payload) + [0])
      return value
    }()
    try await firstContext.withTransaction { transaction in
      try await transaction.save(
        tamperedPreparedDirectory,
        precondition: .exists
      )
    }
    #expect(await firstAttachment.close() == .closed)

    let resumedAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await resumedAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      )
    }
    let resumedRepairContext = try await resumedAttachment.context()
    try await resumedRepairContext.withTransaction { transaction in
      try await transaction.save(preparedDirectory, precondition: .exists)
    }
    #expect(
      try await resumedAttachment.commitStatus(
        operation: operation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )
    let resumed = try await resumedAttachment.submit(
      submission,
      databaseID: genesisRequest.databaseID,
      authorizationSubjectScopeID: genesisRequest.authorizationSubjectScopeID
    )
    let receipt: DesignCommitReceipt
    switch resumed {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("Resumed staging was rejected: \(rejection)")
      _ = await resumedAttachment.close()
      return
    case .outcomeUnknown:
      Issue.record("Resumed staging returned an unknown outcome.")
      _ = await resumedAttachment.close()
      return
    }
    #expect(receipt.candidateRevision == candidateRevision)
    _ = try await resumedAttachment.snapshotDescriptor(
      at: receipt.candidateRevision,
      expectedDatabaseID: genesisRequest.databaseID
    )
    let resumedContext = try await resumedAttachment.context()
    let finalState = try await resumedContext.withTransaction {
      transaction in
      let first = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: candidateRevision.revisionID.description + "-0",
        consistency: .serializable
      )
      let last = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: candidateRevision.revisionID.description
          + "-" + String(writeCount - 1),
        consistency: .serializable
      )
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let stagingRoot = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(operation),
        consistency: .serializable
      )
      let reachability = try await transaction.fetch(
        DesignReachabilityStateModel.self,
        identifiedBy: "active",
        consistency: .serializable
      )
      return (first, last, intent, stagingRoot, reachability)
    }
    #expect(finalState.0?.name == "staged-0")
    #expect(finalState.1?.name == "staged-" + String(writeCount - 1))
    let committedIntent = try #require(finalState.2)
    #expect(committedIntent.state == DesignCommitBuildIntentState.committed.rawValue)
    #expect(committedIntent.stagedDomainWriteCount == writeCount)
    #expect(
      committedIntent.stagedProjectionNodeCount
        == committedIntent.expectedProjectionNodeCount
    )
    let publishedStagingRoot = try #require(finalState.3)
    #expect(
      publishedStagingRoot.state
        == DesignDatabaseRuntimeStagingRootState.published.rawValue
    )
    #expect(
      publishedStagingRoot.reachabilityGeneration
        > activeStagingRoot.reachabilityGeneration
    )
    #expect(
      finalState.4?.generation
        == publishedStagingRoot.reachabilityGeneration
    )
    #expect(await resumedAttachment.close() == .closed)
    let preparationCounts = preparationCounter.counts()
    #expect(preparationCounts.validation == 1)
    #expect(preparationCounts.materialization == 2)
  }

  @Test("Qualified maintenance abandonment terminalizes exact active staging")
  func qualifiedCommitAbandonmentTerminalizesActiveStaging() async throws {
    let stagingLimit = DesignDatabaseRuntimeCommitBuildIntent
      .stagingTransactionWriteLimit
    let writeCount = stagingLimit + 2
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestResumableMutationAdapter(
            writeCount: writeCount,
            failureGate: RuntimeTestStagingFailureGate(
              failureIndex: stagingLimit
            ),
            preparationCounter: RuntimeTestPreparationCounter()
          )
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["qualified-commit-abandonment"]
    )
    let attachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: DisabledTestContainerProvider()
    ).open(locator: locator, registration: registration)
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "qualified-abandonment-create",
      genesisLow: 712
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "qualified-abandonment-target",
      payload: Array("abandoned".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest,
      expectedWriteCount: writeCount
    )
    let targetOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.submit(
        submission,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      )
    }
    #expect(
      try await attachment.commitStatus(
        operation: targetOperation,
        requestDigest: submission.requestDigest
      ) == .inProgress
    )

    let request = try commitAbandonmentRequest(
      operation: "qualified-abandonment-operation",
      targetOperation: targetOperation,
      targetRequestDigest: submission.requestDigest
    )
    let firstResult = try await attachment.abandonCommit(
      request,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    )
    let receipt: DesignCommitAbandonmentReceipt
    switch firstResult {
    case .abandoned(let abandoned):
      receipt = abandoned
      #expect(abandoned.stagingRootTerminalized)
    case .rejected(let rejection):
      Issue.record("Exact active staging abandonment was rejected: \(rejection)")
      _ = await attachment.close()
      return
    case .outcomeUnknown:
      Issue.record("Exact active staging abandonment returned an unknown outcome.")
      _ = await attachment.close()
      return
    }
    #expect(
      try await attachment.abandonCommit(
        request,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      ) == firstResult
    )
    let abandonmentOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: request.operationID
    )
    #expect(
      try await attachment.commitAbandonmentStatus(
        operation: abandonmentOperation,
        requestDigest: request.requestDigest
      ) == .abandoned(receipt)
    )

    let targetRejection: DesignCommitRejection
    switch try await attachment.commitStatus(
      operation: targetOperation,
      requestDigest: submission.requestDigest
    ) {
    case .rejected(let rejection):
      targetRejection = rejection
      guard case .abandonedByMaintenance(
        let maintenanceOperation,
        let maintenanceRequestDigest,
        let reason,
        let evidenceDigest
      ) = rejection.reason else {
        Issue.record("The target rejection omitted its maintenance binding.")
        _ = await attachment.close()
        return
      }
      #expect(maintenanceOperation == abandonmentOperation)
      #expect(maintenanceRequestDigest == request.requestDigest)
      #expect(reason == request.reason)
      #expect(evidenceDigest == request.evidenceDigest)
      #expect(rejection.outcomeDigest == receipt.targetCommitOutcomeDigest)
    default:
      Issue.record("The abandoned target commit did not become rejected.")
      _ = await attachment.close()
      return
    }
    switch try await attachment.submit(
      submission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .rejected(let replayed):
      #expect(replayed == targetRejection)
    default:
      Issue.record("The abandoned target commit resumed instead of replaying rejection.")
    }

    let context = try await attachment.context()
    let persisted = try await context.withTransaction { transaction in
      let key = DesignDatabaseRuntimeOperationClaim.key(targetOperation)
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let root = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let reachability = try await DesignDatabaseRuntimeReachability.require(
        databaseID: create.databaseID,
        transaction: transaction
      )
      return (intent, root, reachability)
    }
    #expect(
      persisted.0?.state == DesignCommitBuildIntentState.rejected.rawValue
    )
    #expect(
      persisted.1?.state
        == DesignDatabaseRuntimeStagingRootState.rejected.rawValue
    )
    #expect(persisted.2.generation == Int64(receipt.reachabilityGeneration))
    #expect(persisted.1?.reachabilityGeneration == persisted.2.generation)

    let alreadyRejectedRequest = try commitAbandonmentRequest(
      operation: "qualified-abandonment-after-terminal",
      targetOperation: targetOperation,
      targetRequestDigest: submission.requestDigest
    )
    let alreadyRejected = try await attachment.abandonCommit(
      alreadyRejectedRequest,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    )
    guard case .rejected(let alreadyRejectedOutcome) = alreadyRejected,
          case .targetAlreadyRejected(let outcomeDigest)
            = alreadyRejectedOutcome.reason else {
      Issue.record("A terminal target did not return a typed abandonment rejection.")
      _ = await attachment.close()
      return
    }
    #expect(outcomeDigest == targetRejection.outcomeDigest)
    #expect(
      try await attachment.abandonCommit(
        alreadyRejectedRequest,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      ) == alreadyRejected
    )
    try await attachment.validateCommitRecoveryBeforeServingOpens()
    #expect(await attachment.close() == .closed)
  }

  @Test("Qualified maintenance abandonment terminalizes exact pre-intent commit")
  func qualifiedCommitAbandonmentTerminalizesPreIntentCommit() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestPreIntentMutationAdapter(
            counter: RuntimeTestPreparationCounter(),
            failureGate: RuntimeTestMaterializationFailureGate()
          )
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["qualified-pre-intent-abandonment"]
    )
    let attachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: DisabledTestContainerProvider()
    ).open(locator: locator, registration: registration)
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "qualified-pre-intent-create",
      genesisLow: 714
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let base = try await attachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let submission = try mutationSubmission(
      operation: "qualified-pre-intent-target",
      payload: Array("pre-intent".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      dependencyGraphDigest: base.semanticDependencyGraphDigest
    )
    let targetOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: submission.operationID
    )
    await #expect(throws: DesignDatabaseRuntimeError.self) {
      _ = try await attachment.submit(
        submission,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      )
    }
    let request = try commitAbandonmentRequest(
      operation: "qualified-pre-intent-abandonment",
      targetOperation: targetOperation,
      targetRequestDigest: submission.requestDigest
    )
    let result = try await attachment.abandonCommit(
      request,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    )
    guard case .abandoned(let receipt) = result else {
      Issue.record("An exact pre-intent commit was not abandoned.")
      _ = await attachment.close()
      return
    }
    #expect(!receipt.stagingRootTerminalized)
    let context = try await attachment.context()
    let persisted = try await context.withTransaction { transaction in
      let key = DesignDatabaseRuntimeOperationClaim.key(targetOperation)
      let intent = try await transaction.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      let root = try await transaction.fetch(
        DesignStagingRootModel.self,
        identifiedBy: key,
        consistency: .serializable
      )
      return (intent, root)
    }
    #expect(persisted.0 == nil)
    #expect(persisted.1 == nil)
    guard case .rejected(let targetRejection) = try await attachment
      .commitStatus(
        operation: targetOperation,
        requestDigest: submission.requestDigest
      ), case .abandonedByMaintenance = targetRejection.reason else {
      Issue.record("The pre-intent target did not persist its maintenance rejection.")
      _ = await attachment.close()
      return
    }
    #expect(await attachment.close() == .closed)
  }

  @Test("Maintenance handle requires an administered grant")
  func maintenanceHandleRequiresAdministerGrant() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["maintenance-grant"]
    )
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "maintenance-grant-create",
      genesisLow: 713
    )
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: SecurityEnabledContainerProvider(),
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      creationRequestedAuthorization: DesignDatabaseAuthorizationGrantSet([
        .read
      ]),
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let handle = try await provider.create(
      DesignDatabaseCreateRequest(
        locator: locator,
        databaseID: create.databaseID,
        genesisRevisionID: create.genesisRevisionID,
        operationID: create.operationID,
        initialSchemaBundle: registration.designSchemaBundle,
        declaredFeatureCapabilities: create.declaredFeatureCapabilities,
        requestDigest: create.requestDigest
      )
    )
    guard let maintenance = handle as? any DesignDatabaseMaintenanceHandle else {
      Issue.record("The Runtime handle omitted its maintenance capability.")
      _ = await handle.close()
      _ = await provider.close()
      return
    }
    let target = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(rawValue: "unrecorded-target")
    )
    let request = try commitAbandonmentRequest(
      operation: "unauthorized-abandonment",
      targetOperation: target,
      targetRequestDigest: try digest(repeating: "a")
    )
    do {
      _ = try await maintenance.abandonCommit(request)
      Issue.record("A handle without administer grant abandoned a commit.")
    } catch let error {
      #expect(
        error == .unauthorized(
          grant: .administer,
          subjectScopeID: create.authorizationSubjectScopeID
        )
      )
    }
    #expect(await handle.close() == .closed)
    #expect(await provider.close() == .closed)
  }

  @Test("Exact dependency lock survives reopen and rejects persisted tamper")
  func persistentDependencyLockReopenAndTamper() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestMutationAdapter()
        ),
      ]
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-dependency-lock-" + UUID().uuidString,
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      do {
        try FileManager.default.removeItem(at: temporaryDirectory)
      } catch {
        Issue.record(
          "The dependency-lock test could not remove its temporary database: \(error)"
        )
      }
    }
    let provider = ReopenableSQLiteContainerProvider(
      databasePath: temporaryDirectory
        .appendingPathComponent("design.sqlite")
        .path(percentEncoded: false)
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["persistent-dependency-lock"]
    )
    let firstAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let request = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "dependency-lock-create",
      genesisLow: 730
    )
    _ = try await firstAttachment.createGenesis(request)
    let genesis = DesignRevisionReference(
      databaseID: request.databaseID,
      revisionID: request.genesisRevisionID
    )
    let base = try await firstAttachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: request.databaseID
    )
    #expect(base.designSchemaBundle == registration.designSchemaBundle)
    #expect(base.directDependencyLock.entries.isEmpty)

    let lock = try DesignDependencyLock(entries: [
      DesignDependencyLockEntry(
        dependencyID: DesignDependencyID(rawValue: "exact-library"),
        semanticRole: "standard-cell-library",
        target: .databaseRevision(DesignRevisionReference(
          databaseID: DesignDatabaseID(high: 731, low: 732),
          revisionID: DesignRevisionID(high: 733, low: 734)
        )),
        requiredSchemas: registration.designSchemaBundle.members,
        interfaceDigest: try digest(repeating: "b"),
        retentionContractIdentity: "not-required"
      ),
    ])
    let lockRoot = try DesignDependencyLockDigest.root(
      lock,
      using: SHA256ContentDigester()
    )
    let graphDigest = try digest(repeating: "c")
    let update = try DesignDependencyLockUpdate(
      replacement: lock,
      dependencyRootDigest: lockRoot,
      semanticDependencyGraphDigest: graphDigest
    )
    let budget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1,
      maximumPreparedWriteCount: 1,
      maximumValidationReadCount: 1
    )
    let sourceEvidence = try digest(repeating: "d")
    let planDigest = try DesignMutationPlanDigest.plan(
      databaseID: request.databaseID,
      baseRevision: genesis,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      semanticDependencyGraphDigest: base.semanticDependencyGraphDigest,
      sourceEvidenceDigest: sourceEvidence,
      budget: budget,
      segments: [],
      dependencyLockUpdate: update,
      using: SHA256ContentDigester()
    )
    let plan = DesignMutationPlan(
      databaseID: request.databaseID,
      baseRevision: genesis,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: base.dependencyRootDigest,
      semanticDependencyGraphDigest: base.semanticDependencyGraphDigest,
      sourceEvidenceDigest: sourceEvidence,
      budget: budget,
      segments: [],
      planDigest: planDigest,
      dependencyLockUpdate: update
    )
    let operationID = try DesignDatabaseOperationID(
      rawValue: "dependency-lock-candidate"
    )
    let submission = DesignCommitSubmission(
      operationID: operationID,
      plan: plan,
      requestDigest: try DesignMutationPlanDigest.request(
        operationID: operationID,
        planDigest: planDigest,
        using: SHA256ContentDigester()
      )
    )
    let receipt: DesignCommitReceipt
    switch try await firstAttachment.submit(
      submission,
      databaseID: request.databaseID,
      authorizationSubjectScopeID: request.authorizationSubjectScopeID
    ) {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("The dependency-lock candidate was rejected: \(rejection)")
      _ = await firstAttachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The dependency-lock candidate outcome was unknown.")
      _ = await firstAttachment.close()
      return
    }
    #expect(await firstAttachment.close() == .closed)

    let reopenedAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let reopened = try await reopenedAttachment.snapshotDescriptor(
      at: receipt.candidateRevision,
      expectedDatabaseID: request.databaseID
    )
    #expect(reopened.directDependencyLock == lock)
    #expect(reopened.dependencyRootDigest == lockRoot)
    #expect(reopened.semanticDependencyGraphDigest == graphDigest)
    #expect(reopened.designSchemaBundle == registration.designSchemaBundle)

    let context = try await reopenedAttachment.context()
    try await context.withTransaction { transaction in
      guard var manifest = try await transaction.fetch(
        DesignRevisionManifestModel.self,
        identifiedBy: receipt.candidateRevision.revisionID.description,
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimeError.revisionNotFound(
          receipt.candidateRevision.revisionID.description
        )
      }
      manifest.dependencyLockEntries.append(" ")
      try await transaction.save(manifest, precondition: .exists)
    }
    do {
      _ = try await reopenedAttachment.snapshotDescriptor(
        at: receipt.candidateRevision,
        expectedDatabaseID: request.databaseID
      )
      Issue.record("A non-canonical persisted dependency lock was accepted.")
    } catch DesignDatabaseRuntimeError.persistedStateCorrupt(let reason) {
      #expect(
        reason == "A revision manifest dependency lock is not canonical."
      )
    } catch {
      Issue.record("Dependency-lock tamper used the wrong typed failure: \(error)")
    }
    #expect(await reopenedAttachment.close() == .closed)
  }

  @Test("Permanent identity reservations survive rejection, replay, and reopen")
  func permanentIdentityReservationLifecycle() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestMutationAdapter()
        ),
      ]
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-identity-reservation-" + UUID().uuidString,
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      do {
        try FileManager.default.removeItem(at: temporaryDirectory)
      } catch {
        Issue.record(
          "The identity reservation test could not remove its temporary database: \(error)"
        )
      }
    }
    let provider = ReopenableSQLiteContainerProvider(
      databasePath: temporaryDirectory
        .appendingPathComponent("design.sqlite")
        .path(percentEncoded: false)
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["identity-reservation"]
    )
    let firstAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "identity-create",
      genesisLow: 720
    )
    _ = try await firstAttachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let genesisDescriptor = try await firstAttachment.snapshotDescriptor(
      at: genesis,
      expectedDatabaseID: create.databaseID
    )
    let firstIdentityPlan = try DesignMutationIdentityPlan(
      provisionalEntityIDs: [
        DesignProvisionalEntityID(rawValue: "entity-b"),
        DesignProvisionalEntityID(rawValue: "entity-a"),
      ],
      provisionalRelationOccurrenceIDs: [
        DesignProvisionalRelationOccurrenceID(rawValue: "edge-b"),
        DesignProvisionalRelationOccurrenceID(rawValue: "edge-a"),
      ]
    )
    let firstSubmission = try mutationSubmission(
      operation: "identity-first",
      payload: Array("identity".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: genesisDescriptor.dependencyRootDigest,
      dependencyGraphDigest: genesisDescriptor.semanticDependencyGraphDigest,
      identityPlan: firstIdentityPlan
    )
    let firstReceipt: DesignCommitReceipt
    switch try await firstAttachment.submit(
      firstSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let receipt):
      firstReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The first identity reservation was rejected: \(rejection)")
      _ = await firstAttachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The first identity reservation outcome was unknown.")
      _ = await firstAttachment.close()
      return
    }
    let firstContext = try await firstAttachment.context()
    let firstPersistedState = try await firstContext.withTransaction {
      transaction in
      let entity = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: firstReceipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      let allocator = try await transaction.fetch(
        DesignIdentityAllocatorStateModel.self,
        identifiedBy: "active",
        consistency: .serializable
      )
      return (entity, allocator)
    }
    #expect(
      firstPersistedState.0?.name
        == "0000000000000001,0000000000000002|0000000000000001,0000000000000002"
    )
    #expect(firstPersistedState.1?.nextEntityValue == 2)
    #expect(firstPersistedState.1?.nextRelationOccurrenceValue == 2)

    let rejectedIdentityPlan = try DesignMutationIdentityPlan(
      provisionalEntityIDs: [
        DesignProvisionalEntityID(rawValue: "rejected-entity"),
      ],
      provisionalRelationOccurrenceIDs: [
        DesignProvisionalRelationOccurrenceID(rawValue: "rejected-edge"),
      ]
    )
    let firstCandidateDescriptor = try await firstAttachment.snapshotDescriptor(
      at: firstReceipt.candidateRevision,
      expectedDatabaseID: create.databaseID
    )
    let rejectedSubmission = try mutationSubmission(
      operation: "identity-rejected",
      payload: Array("reject".utf8),
      databaseID: create.databaseID,
      baseRevision: firstReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: firstCandidateDescriptor.dependencyRootDigest,
      dependencyGraphDigest: firstCandidateDescriptor.semanticDependencyGraphDigest,
      identityPlan: rejectedIdentityPlan
    )
    switch try await firstAttachment.submit(
      rejectedSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .rejected:
      break
    default:
      Issue.record("The validation fixture did not reject its reserved identities.")
    }
    let rejectedOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: rejectedSubmission.operationID
    )
    switch try await firstAttachment.commitStatus(
      operation: rejectedOperation,
      requestDigest: rejectedSubmission.requestDigest
    ) {
    case .rejected:
      break
    default:
      Issue.record("A rejected identity reservation was not status-visible.")
    }
    #expect(await firstAttachment.close() == .closed)

    let reopenedAttachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: provider
    ).open(locator: locator, registration: registration)
    let finalIdentityPlan = try DesignMutationIdentityPlan(
      provisionalEntityIDs: [
        DesignProvisionalEntityID(rawValue: "final-entity"),
      ],
      provisionalRelationOccurrenceIDs: [
        DesignProvisionalRelationOccurrenceID(rawValue: "final-edge"),
      ]
    )
    let finalSubmission = try mutationSubmission(
      operation: "identity-final",
      payload: Array("identity".utf8),
      databaseID: create.databaseID,
      baseRevision: firstReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: firstCandidateDescriptor.dependencyRootDigest,
      dependencyGraphDigest: firstCandidateDescriptor.semanticDependencyGraphDigest,
      identityPlan: finalIdentityPlan
    )
    let finalReceipt: DesignCommitReceipt
    switch try await reopenedAttachment.submit(
      finalSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let receipt):
      finalReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The final identity reservation was rejected: \(rejection)")
      _ = await reopenedAttachment.close()
      return
    case .outcomeUnknown:
      Issue.record("The final identity reservation outcome was unknown.")
      _ = await reopenedAttachment.close()
      return
    }
    switch try await reopenedAttachment.submit(
      finalSubmission,
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID
    ) {
    case .committed(let replayed):
      #expect(replayed == finalReceipt)
    default:
      Issue.record("An exact identity reservation replay did not return its receipt.")
    }
    let finalContext = try await reopenedAttachment.context()
    let finalPersistedState = try await finalContext.withTransaction {
      transaction in
      let entity = try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: finalReceipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
      let allocator = try await transaction.fetch(
        DesignIdentityAllocatorStateModel.self,
        identifiedBy: "active",
        consistency: .serializable
      )
      return (entity, allocator)
    }
    #expect(
      finalPersistedState.0?.name
        == "0000000000000004|0000000000000004"
    )
    #expect(finalPersistedState.1?.nextEntityValue == 4)
    #expect(finalPersistedState.1?.nextRelationOccurrenceValue == 4)
    #expect(finalPersistedState.1?.generation == 3)
    #expect(await reopenedAttachment.close() == .closed)
  }

  @Test("Entity projection bootstraps, reopens, inherits, updates, and rejects stale before")
  func entityProjectionPublicationLifecycle() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestProjectedMutationAdapter()
        ),
      ]
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-entity-projection-" + UUID().uuidString,
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer {
      do {
        try FileManager.default.removeItem(at: temporaryDirectory)
      } catch {
        Issue.record(
          "The entity projection test could not remove its temporary database: \(error)"
        )
      }
    }
    let containerProvider = ReopenableSQLiteContainerProvider(
      databasePath: temporaryDirectory
        .appendingPathComponent("design.sqlite")
        .path(percentEncoded: false),
      security: .enabled(
        adminRoles: [DesignDatabaseRuntimeStorageSecurity.administratorRole]
      )
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["entity-projection"]
    )
    let genesisRequest = try self.genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "entity-projection-create",
      genesisLow: 730
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .proposeCandidate,
      .inspectOwnOperationOutcome,
    ])
    let firstProvider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: containerProvider,
      authorizationSubjectScopeID: genesisRequest.authorizationSubjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let firstHandle = try await firstProvider.create(
      DesignDatabaseCreateRequest(
        locator: locator,
        databaseID: genesisRequest.databaseID,
        genesisRevisionID: genesisRequest.genesisRevisionID,
        operationID: genesisRequest.operationID,
        initialSchemaBundle: registration.designSchemaBundle,
        declaredFeatureCapabilities: genesisRequest.declaredFeatureCapabilities,
        requestDigest: genesisRequest.requestDigest
      )
    )
    let genesis = DesignRevisionReference(
      databaseID: genesisRequest.databaseID,
      revisionID: genesisRequest.genesisRevisionID
    )
    let genesisSnapshot = try await firstHandle.openSnapshot(at: genesis)
    let bootstrapSubmission = try mutationSubmission(
      operation: "entity-projection-bootstrap",
      payload: Array("bootstrap".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: genesisSnapshot.dependencyRootDigest,
      dependencyGraphDigest: genesisSnapshot.semanticDependencyGraphDigest,
      identityPlan: DesignMutationIdentityPlan(
        provisionalEntityIDs: [
          DesignProvisionalEntityID(rawValue: "top-module"),
        ],
        provisionalRelationOccurrenceIDs: []
      )
    )
    #expect(await genesisSnapshot.close() == .closed)

    let bootstrapReceipt: DesignCommitReceipt
    switch try await firstHandle.submit(bootstrapSubmission) {
    case .committed(let receipt):
      bootstrapReceipt = receipt
    case .rejected(let rejection):
      Issue.record("Entity projection bootstrap was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("Entity projection bootstrap outcome was unknown.")
      return
    }
    let queryBudget = try DesignQueryBudget(
      maximumResultCount: 8,
      maximumNodeFetchCount: 32,
      maximumEncodedReadByteCount: 1_048_576,
      maximumDecodedByteCount: 1_048_576,
      maximumOutputByteCount: 1_048_576,
      maximumWorkCount: 256
    )
    let bootstrapSnapshot = try await firstHandle.openSnapshot(
      at: bootstrapReceipt.candidateRevision
    )
    #expect(bootstrapSnapshot.projectionSemantics.map(\.family) == [.entity, .facet])
    let bootstrapBinding = try #require(
      bootstrapSnapshot.materializationBindings[.entity]
    )
    let bootstrapPage = try await bootstrapSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 8,
        budget: queryBudget
      )
    )
    let runtimeBootstrapSnapshot = try #require(
      bootstrapSnapshot as? DesignDatabaseRuntimeSnapshot
    )
    let coldCacheMetrics = await runtimeBootstrapSnapshot
      .decodedProjectionPageCacheMetrics()
    let warmBootstrapPage = try await bootstrapSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 8,
        budget: queryBudget
      )
    )
    let warmCacheMetrics = await runtimeBootstrapSnapshot
      .decodedProjectionPageCacheMetrics()
    #expect(warmBootstrapPage.rows == bootstrapPage.rows)
    #expect(warmBootstrapPage.report == bootstrapPage.report)
    #expect(warmCacheMetrics.hitCount > coldCacheMetrics.hitCount)
    #expect(
      warmCacheMetrics.databaseReadCount
        == coldCacheMetrics.databaseReadCount
    )
    #expect(
      warmCacheMetrics.decodeAttemptCount
        == coldCacheMetrics.decodeAttemptCount
    )
    #expect(
      warmCacheMetrics.payloadMaterializationByteCount
        == coldCacheMetrics.payloadMaterializationByteCount
    )
    #expect(
      warmCacheMetrics.avoidedPayloadMaterializationByteCount
        - coldCacheMetrics.avoidedPayloadMaterializationByteCount
        == warmBootstrapPage.report.encodedReadByteCount
    )
    #expect(warmCacheMetrics.activeLeaseCount == 0)
    let bootstrapRecord = try DesignEntityProjectionRecord(
      projectionEntry: try #require(bootstrapPage.rows.first)
    )
    let expectedEntityID = try DesignEntityID(rawValue: 1)
    let expectedFacetID = try DesignFacetID(rawValue: "logic")
    #expect(bootstrapRecord.entityID == expectedEntityID)
    #expect(bootstrapRecord.facetID == expectedFacetID)
    let dependencyRootDigest = bootstrapSnapshot.dependencyRootDigest
    let dependencyGraphDigest = bootstrapSnapshot.semanticDependencyGraphDigest
    #expect(await bootstrapSnapshot.close() == .closed)
    #expect(await firstProvider.close() == .closed)

    let reopenedProvider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: containerProvider,
      authorizationSubjectScopeID: genesisRequest.authorizationSubjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let reopenedHandle = try await reopenedProvider.open(
      DesignDatabaseOpenRequest(
        locator: locator,
        expectedDatabaseID: genesisRequest.databaseID,
        requiredFeatureCapabilities: try DesignCapabilitySet([]),
        requestedAuthorization: grants
      )
    )
    let reopenedBootstrapSnapshot = try await reopenedHandle.openSnapshot(
      at: bootstrapReceipt.candidateRevision
    )
    let reopenedPage = try await reopenedBootstrapSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 8,
        budget: queryBudget
      )
    )
    #expect(reopenedPage.rows == bootstrapPage.rows)
    #expect(await reopenedBootstrapSnapshot.close() == .closed)

    let inheritSubmission = try mutationSubmission(
      operation: "entity-projection-inherit",
      payload: Array("inherit".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: bootstrapReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest
    )
    let inheritReceipt: DesignCommitReceipt
    switch try await reopenedHandle.submit(inheritSubmission) {
    case .committed(let receipt):
      inheritReceipt = receipt
    case .rejected(let rejection):
      Issue.record("Entity projection inheritance was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("Entity projection inheritance outcome was unknown.")
      return
    }
    let inheritedSnapshot = try await reopenedHandle.openSnapshot(
      at: inheritReceipt.candidateRevision
    )
    let inheritedBinding = try #require(
      inheritedSnapshot.materializationBindings[.entity]
    )
    #expect(inheritedBinding == bootstrapBinding)
    let inheritedPage = try await inheritedSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 8,
        budget: queryBudget
      )
    )
    #expect(inheritedPage.rows == bootstrapPage.rows)

    let updateSubmission = try mutationSubmission(
      operation: "entity-projection-update",
      payload: Array("update".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: inheritReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: inheritedSnapshot.dependencyRootDigest,
      dependencyGraphDigest: inheritedSnapshot.semanticDependencyGraphDigest
    )
    #expect(await inheritedSnapshot.close() == .closed)
    let updateReceipt: DesignCommitReceipt
    switch try await reopenedHandle.submit(updateSubmission) {
    case .committed(let receipt):
      updateReceipt = receipt
    case .rejected(let rejection):
      Issue.record("Projection path-copy update was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("Projection path-copy update outcome was unknown.")
      return
    }
    let updatedSnapshot = try await reopenedHandle.openSnapshot(
      at: updateReceipt.candidateRevision
    )
    let updatedBinding = try #require(
      updatedSnapshot.materializationBindings[.entity]
    )
    #expect(updatedBinding.bindingGeneration == bootstrapBinding.bindingGeneration + 1)
    #expect(updatedBinding.rootNodeDigest != bootstrapBinding.rootNodeDigest)
    let updatedPage = try await updatedSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 8,
        budget: queryBudget
      )
    )
    let updatedRecord = try DesignEntityProjectionRecord(
      projectionEntry: try #require(updatedPage.rows.first)
    )
    #expect(updatedRecord.contentDigest == dependencyRootDigest)
    let updatedDependencyRoot = updatedSnapshot.dependencyRootDigest
    let updatedDependencyGraph = updatedSnapshot.semanticDependencyGraphDigest

    let staleSubmission = try mutationSubmission(
      operation: "entity-projection-stale",
      payload: Array("stale".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: updateReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: updatedDependencyRoot,
      dependencyGraphDigest: updatedDependencyGraph
    )
    #expect(await updatedSnapshot.close() == .closed)
    switch try await reopenedHandle.submit(staleSubmission) {
    case .rejected(let rejection):
      switch rejection.reason {
      case .invalidSegmentPayload(_, let reason):
        #expect(reason.contains("before value"))
      default:
        Issue.record("Stale projection update used the wrong rejection contract.")
      }
    case .committed:
      Issue.record("A stale projection before value was published.")
    case .outcomeUnknown:
      Issue.record("Stale projection rejection outcome was unknown.")
    }

    let bulkIdentityPlan = try DesignMutationIdentityPlan(
      provisionalEntityIDs: (0..<130).map {
        try DesignProvisionalEntityID(rawValue: "bulk-entity-\($0)")
      },
      provisionalRelationOccurrenceIDs: []
    )
    let bulkSubmission = try mutationSubmission(
      operation: "entity-projection-bulk",
      payload: Array("bulk".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: updateReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: updatedDependencyRoot,
      dependencyGraphDigest: updatedDependencyGraph,
      identityPlan: bulkIdentityPlan
    )
    let bulkReceipt: DesignCommitReceipt
    switch try await reopenedHandle.submit(bulkSubmission) {
    case .committed(let receipt):
      bulkReceipt = receipt
    case .rejected(let rejection):
      Issue.record("Projection split insertion was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("Projection split insertion outcome was unknown.")
      return
    }
    let largeQueryBudget = try DesignQueryBudget(
      maximumResultCount: 256,
      maximumNodeFetchCount: 128,
      maximumEncodedReadByteCount: 8_388_608,
      maximumDecodedByteCount: 8_388_608,
      maximumOutputByteCount: 8_388_608,
      maximumWorkCount: 8_192
    )
    let bulkSnapshot = try await reopenedHandle.openSnapshot(
      at: bulkReceipt.candidateRevision
    )
    let bulkPage = try await bulkSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 256,
        budget: largeQueryBudget
      )
    )
    let bulkEntityIDs = try bulkPage.rows.map {
      try DesignEntityProjectionRecord(projectionEntry: $0).entityID.rawValue
    }
    #expect(bulkEntityIDs == (1...131).map(UInt64.init))
    #expect(bulkPage.continuation == nil)

    let deleteSubmission = try mutationSubmission(
      operation: "entity-projection-bulk-delete",
      payload: Array("bulk-delete".utf8),
      databaseID: genesisRequest.databaseID,
      baseRevision: bulkReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: bulkSnapshot.dependencyRootDigest,
      dependencyGraphDigest: bulkSnapshot.semanticDependencyGraphDigest
    )
    #expect(await bulkSnapshot.close() == .closed)
    let deleteReceipt: DesignCommitReceipt
    switch try await reopenedHandle.submit(deleteSubmission) {
    case .committed(let receipt):
      deleteReceipt = receipt
    case .rejected(let rejection):
      Issue.record("Projection merge deletion was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("Projection merge deletion outcome was unknown.")
      return
    }
    let deleteSnapshot = try await reopenedHandle.openSnapshot(
      at: deleteReceipt.candidateRevision
    )
    let deletePage = try await deleteSnapshot.query(
      DesignQueryRequest(
        family: .entity,
        maximumPageResultCount: 256,
        budget: largeQueryBudget
      )
    )
    let remainingEntityIDs = try deletePage.rows.map {
      try DesignEntityProjectionRecord(projectionEntry: $0).entityID.rawValue
    }
    #expect(remainingEntityIDs == [1, 128, 129, 130, 131])
    #expect(deletePage.continuation == nil)
    #expect(await deleteSnapshot.close() == .closed)
    #expect(await reopenedProvider.close() == .closed)
  }

  @Test("Candidate commit is atomic, replayable, status-visible, and does not promote main")
  func productionCandidateCommit() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestMutationAdapter()
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["provider-commit"]
    )
    let databaseID = try DesignDatabaseID(high: 41, low: 42)
    let genesisRevisionID = DesignRevisionID(high: 0, low: 50)
    let genesis = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: genesisRevisionID
    )
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 43, low: 44)
    let createOperationID = try DesignDatabaseOperationID(rawValue: "commit-create")
    let capabilities = try DesignCapabilitySet([])
    let canonicalCreate = try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesisRevisionID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: createOperationID,
      declaredFeatureCapabilities: capabilities,
      initialSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .proposeCandidate,
      .inspectOwnOperationOutcome,
    ])
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: SecurityEnabledContainerProvider(),
      authorizationSubjectScopeID: subjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let handle = try await provider.create(
      DesignDatabaseCreateRequest(
        locator: locator,
        databaseID: databaseID,
        genesisRevisionID: genesisRevisionID,
        operationID: createOperationID,
        initialSchemaBundle: registration.designSchemaBundle,
        declaredFeatureCapabilities: capabilities,
        requestDigest: canonicalCreate.requestDigest
      )
    )
    let baseSnapshot = try await handle.openSnapshot(at: genesis)
    let dependencyRootDigest = baseSnapshot.dependencyRootDigest
    let dependencyGraphDigest = baseSnapshot.semanticDependencyGraphDigest
    #expect(baseSnapshot.directDependencyLock.entries.isEmpty)
    #expect(baseSnapshot.facetRoots.isEmpty)
    let queryBudget = try DesignQueryBudget(
      maximumResultCount: 16,
      maximumNodeFetchCount: 64,
      maximumEncodedReadByteCount: 1_048_576,
      maximumDecodedByteCount: 1_048_576,
      maximumOutputByteCount: 1_048_576,
      maximumWorkCount: 1_024
    )
    #expect(baseSnapshot.projectionSemantics.map(\.family) == [.facet])
    #expect(baseSnapshot.projectionSemantics.map(\.entryCount) == [0])
    #expect(baseSnapshot.materializationBindings[.facet] != nil)
    let genesisFacetPage = try await baseSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: queryBudget
      )
    )
    #expect(genesisFacetPage.rows.isEmpty)
    #expect(genesisFacetPage.completion == .sourceExhausted)
    #expect(genesisFacetPage.continuation == nil)
    #expect(await baseSnapshot.close() == .closed)

    let submission = try mutationSubmission(
      operation: "commit-candidate",
      payload: Array("top".utf8),
      databaseID: databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest
    )
    let first = try await handle.submit(submission)
    let receipt: DesignCommitReceipt
    switch first {
    case .committed(let committed):
      receipt = committed
    case .rejected(let rejection):
      Issue.record("Candidate commit was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("In-memory candidate commit returned an unknown outcome.")
      return
    }
    #expect(receipt.baseRevision == genesis)
    #expect(receipt.candidateRevision != genesis)
    let candidateSnapshot = try await handle.openSnapshot(
      at: receipt.candidateRevision
    )
    #expect(candidateSnapshot.parents == [genesis])
    #expect(candidateSnapshot.stateDigest == receipt.stateDigest)
    #expect(candidateSnapshot.designSchemaBundleDigest == receipt.designSchemaBundleDigest)
    #expect(candidateSnapshot.dependencyRootDigest == receipt.dependencyRootDigest)
    #expect(candidateSnapshot.directDependencyLock.entries.isEmpty)
    #expect(
      candidateSnapshot.semanticDependencyGraphDigest
        == receipt.semanticDependencyGraphDigest
    )
    #expect(candidateSnapshot.facetRoots == receipt.facetRoots)
    #expect(
      candidateSnapshot.facetRoots == [
        try DesignFacetRoot(
          facetID: DesignFacetID(rawValue: "logic"),
          digest: submission.plan.segments[0].payloadDigest
        ),
      ]
    )
    #expect(candidateSnapshot.directChangeRootDigest == receipt.changeSetDigest)
    #expect(candidateSnapshot.projectionSemantics.map(\.family) == [.facet])
    #expect(candidateSnapshot.projectionSemantics.map(\.entryCount) == [1])
    let candidateFacetPage = try await candidateSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: queryBudget
      )
    )
    #expect(candidateFacetPage.completion == .sourceExhausted)
    #expect(candidateFacetPage.rows.count == 1)
    let candidateFacetRecord = try DesignFacetProjectionRecord(
      projectionEntry: try #require(candidateFacetPage.rows.first)
    )
    #expect(candidateFacetRecord.facetID.rawValue == "logic")
    #expect(candidateFacetRecord.rootDigest == submission.plan.segments[0].payloadDigest)
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await candidateSnapshot.query(
        DesignQueryRequest(
          family: .entity,
          maximumPageResultCount: 1,
          budget: queryBudget
        )
      )
    }
    guard let runtimeSnapshot = candidateSnapshot as? DesignDatabaseRuntimeSnapshot else {
      Issue.record("The production handle did not return its Runtime snapshot owner.")
      return
    }
    let escapedReads = try await runtimeSnapshot.withRuntimeReads(
      maximumReadCount: 3
    ) { reads in
      #expect(reads.revision == receipt.candidateRevision)
      let model = try await reads.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: receipt.candidateRevision.revisionID.description
      )
      #expect(model?.name == "top")
      let intent = try await reads.fetch(
        DesignCommitBuildIntentModel.self,
        identifiedBy: DesignDatabaseRuntimeOperationClaim.key(
          receipt.operation
        )
      )
      #expect(intent?.state == DesignCommitBuildIntentState.committed.rawValue)
      #expect(intent?.stagedDomainWriteCount == 1)
      #expect(intent?.expectedDomainWriteCount == 1)
      #expect(intent?.stagedProjectionNodeCount == intent?.expectedProjectionNodeCount)
      #expect((intent?.expectedProjectionNodeCount ?? 0) > 0)
      let revisionDirectoryModel = try await reads.fetch(
        DesignRevisionPhysicalIdentityDirectoryModel.self,
        identifiedBy: receipt.candidateRevision.revisionID.description
      )
      let revisionDirectory = try
        DesignDatabaseRuntimeRevisionPhysicalIdentityDirectory(
          model: try #require(revisionDirectoryModel),
          revision: receipt.candidateRevision,
          using: SHA256ContentDigester()
        )
      #expect(!revisionDirectory.identities.isEmpty)
      return reads
    }
    await #expect(throws: DesignDatabaseRuntimeReadError.self) {
      _ = try await escapedReads.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: receipt.candidateRevision.revisionID.description
      )
    }
    #expect(await candidateSnapshot.close() == .closed)
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await candidateSnapshot.query(
        DesignQueryRequest(
          family: .facet,
          maximumPageResultCount: 1,
          budget: queryBudget
        )
      )
    }

    let dependencyLock = try DesignDependencyLock(entries: [
      DesignDependencyLockEntry(
        dependencyID: DesignDependencyID(rawValue: "sky130A-pdk"),
        semanticRole: "technology",
        target: .databaseRevision(DesignRevisionReference(
          databaseID: DesignDatabaseID(high: 51, low: 52),
          revisionID: DesignRevisionID(high: 53, low: 54)
        )),
        interfaceDigest: try digest(repeating: "8"),
        retentionContractIdentity: "sky130A-open-reference-v1"
      ),
    ])
    let updatedDependencyRoot = try DesignDependencyLockDigest.root(
      dependencyLock,
      using: SHA256ContentDigester()
    )
    let updatedSemanticGraph = try digest(repeating: "9")
    let dependencyUpdate = try DesignDependencyLockUpdate(
      replacement: dependencyLock,
      dependencyRootDigest: updatedDependencyRoot,
      semanticDependencyGraphDigest: updatedSemanticGraph
    )
    let dependencyBudget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1,
      maximumPreparedWriteCount: 1,
      maximumValidationReadCount: 1
    )
    let dependencyEvidence = try digest(repeating: "a")
    let dependencyPlanDigest = try DesignMutationPlanDigest.plan(
      databaseID: databaseID,
      baseRevision: receipt.candidateRevision,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: receipt.dependencyRootDigest,
      semanticDependencyGraphDigest: receipt.semanticDependencyGraphDigest,
      sourceEvidenceDigest: dependencyEvidence,
      budget: dependencyBudget,
      segments: [],
      dependencyLockUpdate: dependencyUpdate,
      using: SHA256ContentDigester()
    )
    let dependencyPlan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: receipt.candidateRevision,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: receipt.dependencyRootDigest,
      semanticDependencyGraphDigest: receipt.semanticDependencyGraphDigest,
      sourceEvidenceDigest: dependencyEvidence,
      budget: dependencyBudget,
      segments: [],
      planDigest: dependencyPlanDigest,
      dependencyLockUpdate: dependencyUpdate
    )
    let dependencyOperationID = try DesignDatabaseOperationID(
      rawValue: "commit-dependency-candidate"
    )
    let dependencyRequestDigest = try DesignMutationPlanDigest.request(
      operationID: dependencyOperationID,
      planDigest: dependencyPlanDigest,
      using: SHA256ContentDigester()
    )
    let dependencySubmission = DesignCommitSubmission(
      operationID: dependencyOperationID,
      plan: dependencyPlan,
      requestDigest: dependencyRequestDigest
    )
    let dependencyReceipt: DesignCommitReceipt
    switch try await handle.submit(dependencySubmission) {
    case .committed(let committed):
      dependencyReceipt = committed
    case .rejected(let rejection):
      Issue.record("The exact dependency-lock candidate was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The exact dependency-lock candidate outcome was unknown.")
      return
    }
    #expect(dependencyReceipt.dependencyRootDigest == updatedDependencyRoot)
    #expect(
      dependencyReceipt.semanticDependencyGraphDigest == updatedSemanticGraph
    )
    let dependencySnapshot = try await handle.openSnapshot(
      at: dependencyReceipt.candidateRevision
    )
    #expect(dependencySnapshot.directDependencyLock == dependencyLock)
    #expect(dependencySnapshot.dependencyRootDigest == updatedDependencyRoot)
    #expect(
      dependencySnapshot.semanticDependencyGraphDigest == updatedSemanticGraph
    )
    #expect(dependencySnapshot.facetRoots == receipt.facetRoots)
    #expect(await dependencySnapshot.close() == .closed)
    #expect(try await handle.resolve(.named(.main)) == genesis)

    let invalidUpdate = try DesignDependencyLockUpdate(
      replacement: dependencyLock,
      dependencyRootDigest: try digest(repeating: "0"),
      semanticDependencyGraphDigest: updatedSemanticGraph
    )
    let invalidPlanDigest = try DesignMutationPlanDigest.plan(
      databaseID: databaseID,
      baseRevision: receipt.candidateRevision,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: receipt.dependencyRootDigest,
      semanticDependencyGraphDigest: receipt.semanticDependencyGraphDigest,
      sourceEvidenceDigest: dependencyEvidence,
      budget: dependencyBudget,
      segments: [],
      dependencyLockUpdate: invalidUpdate,
      using: SHA256ContentDigester()
    )
    let invalidPlan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: receipt.candidateRevision,
      designSchemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: receipt.dependencyRootDigest,
      semanticDependencyGraphDigest: receipt.semanticDependencyGraphDigest,
      sourceEvidenceDigest: dependencyEvidence,
      budget: dependencyBudget,
      segments: [],
      planDigest: invalidPlanDigest,
      dependencyLockUpdate: invalidUpdate
    )
    let invalidOperationID = try DesignDatabaseOperationID(
      rawValue: "reject-tampered-dependency-root"
    )
    let invalidRequestDigest = try DesignMutationPlanDigest.request(
      operationID: invalidOperationID,
      planDigest: invalidPlanDigest,
      using: SHA256ContentDigester()
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.submit(DesignCommitSubmission(
        operationID: invalidOperationID,
        plan: invalidPlan,
        requestDigest: invalidRequestDigest
      ))
    }
    #expect(
      try await handle.commitStatus(
        operation: DesignDatabaseOperationReference(
          databaseID: databaseID,
          authorizationSubjectScopeID: subjectScopeID,
          operationID: invalidOperationID
        ),
        requestDigest: invalidRequestDigest
      ) == .notRecorded
    )

    let powerSubmission = try mutationSubmission(
      operation: "commit-power-candidate",
      payload: Array("vdd".utf8),
      databaseID: databaseID,
      baseRevision: receipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest,
      targetFacet: "power"
    )
    let powerReceipt: DesignCommitReceipt
    switch try await handle.submit(powerSubmission) {
    case .committed(let committed):
      powerReceipt = committed
    case .rejected(let rejection):
      Issue.record("The second-facet candidate was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The second-facet candidate outcome was unknown.")
      return
    }
    let twoFacetSnapshot = try await handle.openSnapshot(
      at: powerReceipt.candidateRevision
    )
    #expect(twoFacetSnapshot.projectionSemantics.map(\.entryCount) == [2])
    let firstFacetPage = try await twoFacetSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: queryBudget
      )
    )
    #expect(firstFacetPage.completion == .pageLimitReached)
    let firstContinuation = try #require(firstFacetPage.continuation)
    let secondFacetPage = try await twoFacetSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: queryBudget,
        continuation: firstContinuation
      )
    )
    #expect(secondFacetPage.completion == .sourceExhausted)
    #expect(secondFacetPage.continuation == nil)
    let pagedFacetRecords = try (firstFacetPage.rows + secondFacetPage.rows).map(
      DesignFacetProjectionRecord.init
    )
    #expect(pagedFacetRecords.map { $0.facetID.rawValue } == ["logic", "power"])
    #expect(Set(pagedFacetRecords.map(\.facetID)).count == 2)
    let prefixPage = try await twoFacetSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        keyPrefix: DesignCanonicalKey(bytes: Array("power".utf8)),
        maximumPageResultCount: 1,
        budget: queryBudget
      )
    )
    #expect(prefixPage.completion == .sourceExhausted)
    #expect(
      try prefixPage.rows.map(DesignFacetProjectionRecord.init)
        .map { $0.facetID.rawValue } == ["power"]
    )
    let oneResultBudget = try DesignQueryBudget(
      maximumResultCount: 1,
      maximumNodeFetchCount: 64,
      maximumEncodedReadByteCount: 1_048_576,
      maximumDecodedByteCount: 1_048_576,
      maximumOutputByteCount: 1_048_576,
      maximumWorkCount: 1_024
    )
    let budgetTerminalPage = try await twoFacetSnapshot.query(
      DesignQueryRequest(
        family: .facet,
        maximumPageResultCount: 1,
        budget: oneResultBudget
      )
    )
    #expect(budgetTerminalPage.rows.count == 1)
    #expect(budgetTerminalPage.completion == .queryBudgetExhausted)
    #expect(budgetTerminalPage.continuation == nil)
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await twoFacetSnapshot.query(
        DesignQueryRequest(
          family: .facet,
          keyPrefix: DesignCanonicalKey(bytes: Array("power".utf8)),
          maximumPageResultCount: 1,
          budget: queryBudget,
          continuation: firstContinuation
        )
      )
    }
    #expect(await twoFacetSnapshot.close() == .closed)
    #expect(try await handle.resolve(.exact(receipt.candidateRevision)) == receipt.candidateRevision)
    #expect(try await handle.resolve(.named(.main)) == genesis)
    #expect(try await handle.submit(submission) == first)
    #expect(
      try await handle.commitStatus(
        operation: receipt.operation,
        requestDigest: submission.requestDigest
      ) == .committed(receipt)
    )

    let rejectedSubmission = try mutationSubmission(
      operation: "commit-rejected",
      payload: Array("reject".utf8),
      databaseID: databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest
    )
    switch try await handle.submit(rejectedSubmission) {
    case .rejected(let rejection):
      guard case .validationFailed(let diagnostics, _) = rejection.reason else {
        Issue.record("The adapter rejection did not retain typed diagnostics.")
        return
      }
      #expect(diagnostics.map(\.code.rawValue) == ["RUNTIME_TEST_REJECTION"])
      #expect(
        try await handle.commitStatus(
          operation: rejection.operation,
          requestDigest: rejectedSubmission.requestDigest
        ) == .rejected(rejection)
      )
    default:
      Issue.record("A validation failure published a candidate revision.")
    }
    let staleDependencySubmission = try mutationSubmission(
      operation: "commit-stale-dependency",
      payload: Array("stale-dependency".utf8),
      databaseID: databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: try digest(repeating: "d"),
      dependencyGraphDigest: dependencyGraphDigest
    )
    switch try await handle.submit(staleDependencySubmission) {
    case .rejected(let rejection):
      guard case .dependencyRootMismatch(let expected, let actual) = rejection.reason else {
        Issue.record("A stale dependency root did not retain its exact mismatch.")
        return
      }
      #expect(expected == dependencyRootDigest)
      #expect(actual == staleDependencySubmission.plan.dependencyRootDigest)
    default:
      Issue.record("A stale dependency root published a candidate revision.")
    }
    let staleGraphSubmission = try mutationSubmission(
      operation: "commit-stale-graph",
      payload: Array("stale-graph".utf8),
      databaseID: databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: try digest(repeating: "e")
    )
    switch try await handle.submit(staleGraphSubmission) {
    case .rejected(let rejection):
      guard case .dependencyGraphMismatch(let expected, let actual) = rejection.reason else {
        Issue.record("A stale dependency graph did not retain its exact mismatch.")
        return
      }
      #expect(expected == dependencyGraphDigest)
      #expect(actual == staleGraphSubmission.plan.semanticDependencyGraphDigest)
    default:
      Issue.record("A stale dependency graph published a candidate revision.")
    }

    let alternateSubmission = try mutationSubmission(
      operation: "commit-alternate-candidate",
      payload: Array("alternate".utf8),
      databaseID: databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest
    )
    let alternateReceipt: DesignCommitReceipt
    switch try await handle.submit(alternateSubmission) {
    case .committed(let committed):
      alternateReceipt = committed
    case .rejected(let rejection):
      Issue.record("The alternate branch was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The alternate branch outcome was unknown.")
      return
    }
    let forwardDiff = try await handle.diff(
      DesignRevisionDiffRequest(
        fromRevision: genesis,
        toRevision: receipt.candidateRevision,
        budget: DesignRevisionDiffBudget(maximumFacetComparisonCount: 1)
      )
    )
    #expect(forwardDiff.facetChanges.map(\.kind) == [.added])
    #expect(forwardDiff.facetChanges.map(\.facetID.rawValue) == ["logic"])
    let reverseDiff = try await handle.diff(
      DesignRevisionDiffRequest(
        fromRevision: receipt.candidateRevision,
        toRevision: genesis,
        budget: DesignRevisionDiffBudget(maximumFacetComparisonCount: 1)
      )
    )
    #expect(reverseDiff.facetChanges.map(\.kind) == [.removed])

    let mergeAssessment = try await handle.assessDisjointMerge(
      DesignDisjointMergeRequest(
        baseRevision: genesis,
        leftRevision: receipt.candidateRevision,
        rightRevision: alternateReceipt.candidateRevision,
        budget: DesignDisjointMergeBudget(
          maximumFacetComparisonCount: 1,
          maximumAncestryRevisionCount: 3
        )
      )
    )
    guard case .conflict(let mergeConflict) = mergeAssessment else {
      Issue.record("Two divergent logic roots were accepted as disjoint.")
      return
    }
    #expect(mergeConflict.kind == .overlappingFacetChange)
    #expect(mergeConflict.facetIDs.map(\.rawValue) == ["logic"])
    #expect(try await handle.resolve(.named(.main)) == genesis)
    #expect(await handle.close() == .closed)
    #expect(await provider.close() == .closed)
  }

  @Test("Disjoint merge publication requires an exact validated revision and preserves shared writes")
  func validatedDisjointMergePublication() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "disjoint-merge-create",
      genesisLow: 713
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let descriptor = try await attachment.inspectDatabase(
      expectedDatabaseID: create.databaseID,
      requiredFeatureCapabilities: try DesignCapabilitySet([])
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .proposeCandidate,
      .inspectOwnOperationOutcome,
    ])
    let handle = DesignDatabaseRuntimeHandle(
      descriptor: descriptor,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      authorizationGrants: grants,
      authorizer: AllowingRuntimeTestAuthorizer(),
      attachment: attachment
    )
    let genesisSnapshot = try await handle.openSnapshot(at: genesis)
    let dependencyRootDigest = genesisSnapshot.dependencyRootDigest
    let dependencyGraphDigest = genesisSnapshot.semanticDependencyGraphDigest
    #expect(await genesisSnapshot.close() == .closed)

    let leftSubmission = try mutationSubmission(
      operation: "disjoint-merge-left",
      payload: Array("logic-left".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest
    )
    let leftReceipt: DesignCommitReceipt
    switch try await handle.submit(leftSubmission) {
    case .committed(let receipt):
      leftReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The left merge branch was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The left merge branch outcome was unknown.")
      return
    }
    let rightSubmission = try mutationSubmission(
      operation: "disjoint-merge-right",
      payload: Array("power-right".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      dependencyGraphDigest: dependencyGraphDigest,
      targetFacet: "power"
    )
    let rightReceipt: DesignCommitReceipt
    switch try await handle.submit(rightSubmission) {
    case .committed(let receipt):
      rightReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The right merge branch was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The right merge branch outcome was unknown.")
      return
    }
    let assessment = try await handle.assessDisjointMerge(
      DesignDisjointMergeRequest(
        baseRevision: genesis,
        leftRevision: leftReceipt.candidateRevision,
        rightRevision: rightReceipt.candidateRevision,
        budget: DesignDisjointMergeBudget(
          maximumFacetComparisonCount: 2,
          maximumAncestryRevisionCount: 3
        )
      )
    )
    let candidate: DesignDisjointMergeCandidate
    switch assessment {
    case .requiresSemanticValidation(let value):
      candidate = value
    case .conflict(let conflict):
      Issue.record("Disjoint branch changes conflicted: \(conflict)")
      return
    }
    #expect(candidate.leftChangedFacetIDs.count == 1)
    #expect(candidate.rightChangedFacetIDs.count == 1)
    #expect(
      Set(candidate.leftChangedFacetIDs + candidate.rightChangedFacetIDs)
        == Set([
          try DesignFacetID(rawValue: "logic"),
          try DesignFacetID(rawValue: "power"),
        ])
    )

    let validatedSubmission = try mutationSubmission(
      operation: "disjoint-merge-validated-state",
      payload: Array("power-right".utf8),
      databaseID: create.databaseID,
      baseRevision: leftReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: leftReceipt.dependencyRootDigest,
      dependencyGraphDigest: leftReceipt.semanticDependencyGraphDigest,
      targetFacet: "power"
    )
    let validatedReceipt: DesignCommitReceipt
    switch try await handle.submit(validatedSubmission) {
    case .committed(let receipt):
      validatedReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The exact merged-state validation was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The exact merged-state validation outcome was unknown.")
      return
    }
    #expect(validatedReceipt.facetRoots == candidate.facetRoots)
    #expect(validatedReceipt.dependencyRootDigest == candidate.dependencyRootDigest)
    #expect(
      validatedReceipt.semanticDependencyGraphDigest
        == candidate.semanticDependencyGraphDigest
    )

    let publicationBudget = try DesignDisjointMergePublicationBudget(
      maximumProjectionCount: 8,
      maximumPhysicalIdentityCount: 64
    )
    let publicationOperationID = try DesignDatabaseOperationID(
      rawValue: "publish-disjoint-merge"
    )
    let publicationRequestDigest = try DesignDisjointMergePublicationDigest
      .request(
        operationID: publicationOperationID,
        candidate: candidate,
        validatedStateRevision: validatedReceipt.candidateRevision,
        validatedStateCommit: validatedSubmission,
        budget: publicationBudget,
        using: SHA256ContentDigester()
      )
    let publication = try DesignDisjointMergePublicationSubmission(
      operationID: publicationOperationID,
      candidate: candidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: publicationBudget,
      requestDigest: publicationRequestDigest
    )
    await #expect(throws: DesignDatabaseRuntimeError.persistedStateCorrupt(
      reason: "A disjoint-merge validation receipt escaped its exact submission scope."
    )) {
      _ = try await attachment.publishDisjointMerge(
        publication,
        validatedCommitReceipt: leftReceipt,
        assessmentMatches: true,
        databaseID: create.databaseID,
        authorizationSubjectScopeID: create.authorizationSubjectScopeID
      )
    }
    let publicationOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: publicationOperationID
    )
    #expect(
      try await attachment.disjointMergePublicationStatus(
        operation: publicationOperation,
        requestDigest: publicationRequestDigest
      ) == .notRecorded
    )
    let firstPublication = try await handle.publishDisjointMerge(publication)
    let mergeReceipt: DesignDisjointMergePublicationReceipt
    switch firstPublication {
    case .published(let receipt):
      mergeReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The validated disjoint merge was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The validated disjoint merge outcome was unknown.")
      return
    }
    #expect(mergeReceipt.baseRevision == genesis)
    #expect(mergeReceipt.parentRevisions == candidate.parentRevisions)
    #expect(
      mergeReceipt.validatedStateRevision
        == validatedReceipt.candidateRevision
    )
    #expect(mergeReceipt.facetRoots == candidate.facetRoots)
    #expect(mergeReceipt.stateDigest == validatedReceipt.stateDigest)
    #expect(try await handle.publishDisjointMerge(publication) == firstPublication)
    #expect(
      try await handle.disjointMergePublicationStatus(
        operation: mergeReceipt.operation,
        requestDigest: publication.requestDigest
      ) == .published(mergeReceipt)
    )
    #expect(try await handle.resolve(.named(.main)) == genesis)

    let mergedSnapshot = try await handle.openSnapshot(
      at: mergeReceipt.candidateRevision
    )
    #expect(mergedSnapshot.parents == candidate.parentRevisions)
    #expect(mergedSnapshot.stateDigest == validatedReceipt.stateDigest)
    #expect(mergedSnapshot.facetRoots == candidate.facetRoots)
    #expect(await mergedSnapshot.close() == .closed)

    let invalidOperationID = try DesignDatabaseOperationID(
      rawValue: "reject-unvalidated-disjoint-merge"
    )
    let invalidRequestDigest = try DesignDisjointMergePublicationDigest
      .request(
        operationID: invalidOperationID,
        candidate: candidate,
        validatedStateRevision: leftReceipt.candidateRevision,
        validatedStateCommit: leftSubmission,
        budget: publicationBudget,
        using: SHA256ContentDigester()
      )
    let invalidPublication = try DesignDisjointMergePublicationSubmission(
      operationID: invalidOperationID,
      candidate: candidate,
      validatedStateRevision: leftReceipt.candidateRevision,
      validatedStateCommit: leftSubmission,
      budget: publicationBudget,
      requestDigest: invalidRequestDigest
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.publishDisjointMerge(invalidPublication)
    }

    let staleCandidate = try DesignDisjointMergeCandidate(
      baseRevision: candidate.baseRevision,
      parentRevisions: candidate.parentRevisions,
      designSchemaBundleDigest: candidate.designSchemaBundleDigest,
      dependencyRootDigest: candidate.dependencyRootDigest,
      semanticDependencyGraphDigest:
        candidate.semanticDependencyGraphDigest,
      facetRoots: candidate.facetRoots,
      leftChangedFacetIDs: candidate.leftChangedFacetIDs,
      rightChangedFacetIDs: candidate.rightChangedFacetIDs,
      semanticValidationRequirements:
        candidate.semanticValidationRequirements,
      resourceReport: DesignDisjointMergeResourceReport(
        facetComparisonCount: 0,
        ancestryRevisionReadCount:
          candidate.resourceReport.ancestryRevisionReadCount,
        maximumFacetComparisonCount:
          candidate.resourceReport.maximumFacetComparisonCount,
        maximumAncestryRevisionCount:
          candidate.resourceReport.maximumAncestryRevisionCount
      )
    )
    #expect(staleCandidate != candidate)
    let staleOperationID = try DesignDatabaseOperationID(
      rawValue: "reject-stale-disjoint-merge-assessment"
    )
    let staleRequestDigest = try DesignDisjointMergePublicationDigest.request(
      operationID: staleOperationID,
      candidate: staleCandidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: publicationBudget,
      using: SHA256ContentDigester()
    )
    let stalePublication = try DesignDisjointMergePublicationSubmission(
      operationID: staleOperationID,
      candidate: staleCandidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: publicationBudget,
      requestDigest: staleRequestDigest
    )
    let staleRejection: DesignDisjointMergePublicationRejection
    switch try await handle.publishDisjointMerge(stalePublication) {
    case .rejected(let rejection):
      staleRejection = rejection
    case .published:
      Issue.record("The stale merge assessment was published.")
      return
    case .outcomeUnknown:
      Issue.record("The stale merge assessment outcome was unknown.")
      return
    }
    #expect(staleRejection.reason == .assessmentChanged)
    #expect(
      try await handle.disjointMergePublicationStatus(
        operation: staleRejection.operation,
        requestDigest: staleRequestDigest
      ) == .rejected(staleRejection)
    )

    let conflictingBudget = try DesignDisjointMergePublicationBudget(
      maximumProjectionCount: 9,
      maximumPhysicalIdentityCount: 64
    )
    let conflictingPublication = try DesignDisjointMergePublicationSubmission(
      operationID: publicationOperationID,
      candidate: candidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: conflictingBudget,
      requestDigest: try DesignDisjointMergePublicationDigest.request(
        operationID: publicationOperationID,
        candidate: candidate,
        validatedStateRevision: validatedReceipt.candidateRevision,
        validatedStateCommit: validatedSubmission,
        budget: conflictingBudget,
        using: SHA256ContentDigester()
      )
    )
    await #expect(throws: DesignDatabaseError.idempotencyConflict(
      operation: mergeReceipt.operation
    )) {
      _ = try await handle.publishDisjointMerge(conflictingPublication)
    }

    let collectionOperation = DesignDatabaseOperationReference(
      databaseID: create.databaseID,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      operationID: try DesignDatabaseOperationID(
        rawValue: "collect-merge-validation-revision"
      )
    )
    let collectionRequest = try DesignDatabaseRuntimeCollectionAdmissionRequest(
      operation: collectionOperation,
      candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet(
        revisions: [validatedReceipt.candidateRevision]
      ),
      using: SHA256ContentDigester()
    )
    let admittedIntent: DesignCollectionIntentModel
    switch try await attachment.admitRevisionCollection(collectionRequest) {
    case .admitted(let intent):
      admittedIntent = intent
    case .collected:
      Issue.record("The validation revision was collected before admission.")
      return
    case .outcomeUnknown:
      Issue.record("The validation revision collection outcome was unknown.")
      return
    }
    let context = try await attachment.context()
    let collectionDirectoryModel = try await context.withTransaction {
      transaction in
      try await transaction.fetch(
        DesignCollectionPhysicalIdentityDirectoryModel.self,
        identifiedBy: admittedIntent.id,
        consistency: .serializable
      )
    }
    let collectionDirectory = try
      DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory(
        model: try #require(collectionDirectoryModel),
        operation: collectionOperation,
        requestDigest: collectionRequest.requestDigest,
        maximumIdentityCount: 256,
        using: SHA256ContentDigester()
      )
    var collected = false
    for _ in 0...collectionDirectory.identities.count {
      switch try await attachment.sweepRevisionCollection(
        operation: collectionOperation,
        requestDigest: collectionRequest.requestDigest,
        maximumPhysicalDeletionCount: 1
      ) {
      case .collected:
        collected = true
      case .sweeping:
        break
      case .outcomeUnknown:
        Issue.record("The validation revision sweep outcome was unknown.")
        return
      }
      if collected { break }
    }
    #expect(collected)
    let sharedDomainWrite = try await context.withTransaction { transaction in
      try await transaction.fetch(
        RuntimeTestLogicEntity.self,
        identifiedBy: validatedReceipt.candidateRevision.revisionID.description,
        consistency: .serializable
      )
    }
    #expect(sharedDomainWrite?.name == "power-right")
    let survivingMergeSnapshot = try await handle.openSnapshot(
      at: mergeReceipt.candidateRevision
    )
    #expect(survivingMergeSnapshot.facetRoots == candidate.facetRoots)
    #expect(await survivingMergeSnapshot.close() == .closed)
    #expect(await handle.close() == .closed)
  }

  @Test("Dependency-changing merge publication requires facet revalidation in the candidate context")
  func dependencyBoundDisjointMergePublication() async throws {
    let (attachment, registration, locator) = try await makeMutableAttachment()
    let create = try genesisRequest(
      locator: locator,
      designSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest,
      operation: "dependency-merge-create",
      genesisLow: 714
    )
    _ = try await attachment.createGenesis(create)
    let genesis = DesignRevisionReference(
      databaseID: create.databaseID,
      revisionID: create.genesisRevisionID
    )
    let descriptor = try await attachment.inspectDatabase(
      expectedDatabaseID: create.databaseID,
      requiredFeatureCapabilities: try DesignCapabilitySet([])
    )
    let handle = DesignDatabaseRuntimeHandle(
      descriptor: descriptor,
      authorizationSubjectScopeID: create.authorizationSubjectScopeID,
      authorizationGrants: DesignDatabaseAuthorizationGrantSet([
        .read,
        .proposeCandidate,
        .inspectOwnOperationOutcome,
      ]),
      authorizer: AllowingRuntimeTestAuthorizer(),
      attachment: attachment
    )
    let baseSnapshot = try await handle.openSnapshot(at: genesis)
    let originalDependencyRoot = baseSnapshot.dependencyRootDigest
    let originalGraphDigest = baseSnapshot.semanticDependencyGraphDigest
    #expect(await baseSnapshot.close() == .closed)

    let leftSubmission = try mutationSubmission(
      operation: "dependency-merge-left",
      payload: Array("logic-left".utf8),
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: originalDependencyRoot,
      dependencyGraphDigest: originalGraphDigest
    )
    let leftReceipt: DesignCommitReceipt
    switch try await handle.submit(leftSubmission) {
    case .committed(let receipt):
      leftReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The dependency-merge facet branch was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The dependency-merge facet branch outcome was unknown.")
      return
    }

    let dependencyLock = try DesignDependencyLock(entries: [
      DesignDependencyLockEntry(
        dependencyID: DesignDependencyID(rawValue: "technology"),
        semanticRole: "technology",
        target: .databaseRevision(DesignRevisionReference(
          databaseID: DesignDatabaseID(high: 714, low: 20),
          revisionID: DesignRevisionID(high: 714, low: 21)
        )),
        interfaceDigest: try digest(repeating: "7"),
        retentionContractIdentity: "dependency-merge-test"
      ),
    ])
    let mergedDependencyRoot = try DesignDependencyLockDigest.root(
      dependencyLock,
      using: SHA256ContentDigester()
    )
    let mergedGraphDigest = try digest(repeating: "8")
    let dependencyUpdate = try DesignDependencyLockUpdate(
      replacement: dependencyLock,
      dependencyRootDigest: mergedDependencyRoot,
      semanticDependencyGraphDigest: mergedGraphDigest
    )
    let rightSubmission = try dependencySubmission(
      operation: "dependency-merge-right",
      databaseID: create.databaseID,
      baseRevision: genesis,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: originalDependencyRoot,
      dependencyGraphDigest: originalGraphDigest,
      update: dependencyUpdate
    )
    let rightReceipt: DesignCommitReceipt
    switch try await handle.submit(rightSubmission) {
    case .committed(let receipt):
      rightReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The dependency-merge lock branch was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The dependency-merge lock branch outcome was unknown.")
      return
    }

    let assessment = try await handle.assessDisjointMerge(
      DesignDisjointMergeRequest(
        baseRevision: genesis,
        leftRevision: leftReceipt.candidateRevision,
        rightRevision: rightReceipt.candidateRevision,
        budget: DesignDisjointMergeBudget(
          maximumFacetComparisonCount: 1,
          maximumAncestryRevisionCount: 3
        )
      )
    )
    let candidate: DesignDisjointMergeCandidate
    switch assessment {
    case .requiresSemanticValidation(let value):
      candidate = value
    case .conflict(let conflict):
      Issue.record("The dependency-bound branches conflicted: \(conflict)")
      return
    }
    let dependencyRequirement = try #require(
      candidate.semanticValidationRequirements.first {
        $0.kind == .dependencyBinding
      }
    )
    #expect(dependencyRequirement.facetIDs == [
      try DesignFacetID(rawValue: "logic"),
    ])

    let unvalidatedSubmission = try dependencySubmission(
      operation: "dependency-merge-unvalidated-state",
      databaseID: create.databaseID,
      baseRevision: leftReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: leftReceipt.dependencyRootDigest,
      dependencyGraphDigest: leftReceipt.semanticDependencyGraphDigest,
      update: dependencyUpdate
    )
    let unvalidatedReceipt: DesignCommitReceipt
    switch try await handle.submit(unvalidatedSubmission) {
    case .committed(let receipt):
      unvalidatedReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The dependency-only validation fixture was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The dependency-only validation fixture outcome was unknown.")
      return
    }
    #expect(unvalidatedReceipt.facetRoots == candidate.facetRoots)
    let publicationBudget = try DesignDisjointMergePublicationBudget(
      maximumProjectionCount: 8,
      maximumPhysicalIdentityCount: 64
    )
    let unvalidatedOperationID = try DesignDatabaseOperationID(
      rawValue: "reject-dependency-merge-without-facet-validation"
    )
    let unvalidatedRequestDigest = try
      DesignDisjointMergePublicationDigest.request(
        operationID: unvalidatedOperationID,
        candidate: candidate,
        validatedStateRevision: unvalidatedReceipt.candidateRevision,
        validatedStateCommit: unvalidatedSubmission,
        budget: publicationBudget,
        using: SHA256ContentDigester()
      )
    let unvalidatedPublication = try
      DesignDisjointMergePublicationSubmission(
        operationID: unvalidatedOperationID,
        candidate: candidate,
        validatedStateRevision: unvalidatedReceipt.candidateRevision,
        validatedStateCommit: unvalidatedSubmission,
        budget: publicationBudget,
        requestDigest: unvalidatedRequestDigest
      )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await handle.publishDisjointMerge(unvalidatedPublication)
    }

    let validatedSubmission = try mutationSubmission(
      operation: "dependency-merge-validated-state",
      payload: Array("logic-left".utf8),
      databaseID: create.databaseID,
      baseRevision: leftReceipt.candidateRevision,
      schemaBundleDigest: registration.designSchemaBundleDigest,
      dependencyRootDigest: leftReceipt.dependencyRootDigest,
      dependencyGraphDigest: leftReceipt.semanticDependencyGraphDigest,
      dependencyLockUpdate: dependencyUpdate
    )
    let validatedReceipt: DesignCommitReceipt
    switch try await handle.submit(validatedSubmission) {
    case .committed(let receipt):
      validatedReceipt = receipt
    case .rejected(let rejection):
      Issue.record("The dependency-bound facet validation was rejected: \(rejection)")
      return
    case .outcomeUnknown:
      Issue.record("The dependency-bound facet validation outcome was unknown.")
      return
    }
    #expect(validatedReceipt.facetRoots == candidate.facetRoots)
    #expect(validatedReceipt.dependencyRootDigest == candidate.dependencyRootDigest)
    let operationID = try DesignDatabaseOperationID(
      rawValue: "publish-dependency-bound-merge"
    )
    let requestDigest = try DesignDisjointMergePublicationDigest.request(
      operationID: operationID,
      candidate: candidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: publicationBudget,
      using: SHA256ContentDigester()
    )
    let publication = try DesignDisjointMergePublicationSubmission(
      operationID: operationID,
      candidate: candidate,
      validatedStateRevision: validatedReceipt.candidateRevision,
      validatedStateCommit: validatedSubmission,
      budget: publicationBudget,
      requestDigest: requestDigest
    )
    switch try await handle.publishDisjointMerge(publication) {
    case .published(let receipt):
      #expect(receipt.dependencyRootDigest == mergedDependencyRoot)
      #expect(receipt.semanticDependencyGraphDigest == mergedGraphDigest)
      #expect(receipt.validatedStateCommitOperation.operationID
        == validatedSubmission.operationID)
      #expect(receipt.validatedStatePlanDigest
        == validatedSubmission.plan.planDigest)
    case .rejected(let rejection):
      Issue.record("The dependency-bound merge was rejected: \(rejection)")
    case .outcomeUnknown:
      Issue.record("The dependency-bound merge outcome was unknown.")
    }
    #expect(await handle.close() == .closed)
  }

  @Test("Retention activation and release are exact and permanently tombstoned")
  func productionRetentionLifecycle() async throws {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["provider-retention"]
    )
    let databaseID = try DesignDatabaseID(high: 25, low: 26)
    let genesis = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 0, low: 40)
    )
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(high: 27, low: 28)
    let createOperationID = try DesignDatabaseOperationID(
      rawValue: "provider-retention-create"
    )
    let capabilities = try DesignCapabilitySet([])
    let canonicalCreate = try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: databaseID,
      genesisRevisionID: genesis.revisionID,
      authorizationSubjectScopeID: subjectScopeID,
      operationID: createOperationID,
      declaredFeatureCapabilities: capabilities,
      initialSchemaBundle: registration.designSchemaBundle,
      registrationDigest: registration.registrationDigest
    )
    let grants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .retain,
      .promoteReference,
      .inspectOwnOperationOutcome,
    ])
    let provider = DesignDatabaseRuntimeProvider(
      registration: registration,
      containerProvider: SecurityEnabledContainerProvider(),
      authorizationSubjectScopeID: subjectScopeID,
      creationRequestedAuthorization: grants,
      authorizer: AllowingRuntimeTestAuthorizer()
    )
    let handle = try await provider.create(
      DesignDatabaseCreateRequest(
        locator: locator,
        databaseID: databaseID,
        genesisRevisionID: genesis.revisionID,
        operationID: createOperationID,
        initialSchemaBundle: registration.designSchemaBundle,
        declaredFeatureCapabilities: capabilities,
        requestDigest: canonicalCreate.requestDigest
      )
    )
    let claimID = try DesignRevisionRetentionID(rawValue: "release-bundle")
    let retain = try retentionRequest(
      operation: "retain-genesis",
      claimID: claimID,
      revision: genesis
    )
    let first = try await handle.retain(retain)
    let active: DesignRevisionRetentionReceipt
    switch first {
    case .applied(let receipt):
      active = receipt
      #expect(receipt.state == .active)
      #expect(receipt.generation == 1)
      #expect(receipt.reachabilityGeneration == 1)
    default:
      Issue.record("Exact retention activation was not applied.")
      return
    }
    #expect(try await handle.retain(retain) == first)
    #expect(
      try await handle.retentionStatus(
        operation: active.operation,
        requestDigest: retain.requestDigest
      ) == .applied(active)
    )

    let duplicate = try retentionRequest(
      operation: "retain-duplicate",
      claimID: claimID,
      revision: genesis
    )
    switch try await handle.retain(duplicate) {
    case .rejected(let rejection):
      #expect(rejection.reason == .claimAlreadyActive)
    default:
      Issue.record("An active retention claim was accepted twice.")
    }

    let wrongGeneration = try retentionReleaseRequest(
      operation: "release-wrong-generation",
      claimID: claimID,
      revision: genesis,
      generation: active.generation + 1
    )
    switch try await handle.releaseRetention(wrongGeneration) {
    case .rejected(let rejection):
      #expect(rejection.reason == .generationMismatch(actual: 1))
    default:
      Issue.record("A wrong retention generation was not rejected.")
    }

    let release = try retentionReleaseRequest(
      operation: "release-genesis",
      claimID: claimID,
      revision: genesis,
      generation: active.generation
    )
    let released: DesignRevisionRetentionReceipt
    switch try await handle.releaseRetention(release) {
    case .applied(let receipt):
      released = receipt
      #expect(receipt.state == .released)
      #expect(receipt.generation == 2)
      #expect(receipt.reachabilityGeneration == 2)
    default:
      Issue.record("Exact retention release was not applied.")
      return
    }

    let reuse = try retentionRequest(
      operation: "retain-released-id",
      claimID: claimID,
      revision: genesis
    )
    switch try await handle.retain(reuse) {
    case .rejected(let rejection):
      #expect(rejection.reason == .claimPermanentlyReleased)
    default:
      Issue.record("A released retention identifier was reused.")
    }
    #expect(
      try await handle.retentionStatus(
        operation: released.operation,
        requestDigest: release.requestDigest
      ) == .applied(released)
    )
    let conflictingStatusDigest = try digest(repeating: "e")
    switch try await handle.retentionStatus(
      operation: released.operation,
      requestDigest: conflictingStatusDigest
    ) {
    case .rejected(let rejection):
      #expect(rejection.reason == .operationRequestConflict)
    default:
      Issue.record("A conflicting retention status digest was not rejected.")
    }

    let crossKindName = try DesignReferenceName(rawValue: "audit")
    let crossKindReference = try referenceRequest(
      operation: "cross-kind-operation",
      name: crossKindName,
      expectedGeneration: 0,
      expectedRevision: nil,
      desiredRevision: genesis
    )
    _ = try await handle.compareAndSetReference(crossKindReference)
    let crossKindRetention = try retentionRequest(
      operation: "cross-kind-operation",
      claimID: DesignRevisionRetentionID(rawValue: "cross-kind-claim"),
      revision: genesis
    )
    switch try await handle.retain(crossKindRetention) {
    case .rejected(let rejection):
      #expect(rejection.reason == .operationRequestConflict)
    default:
      Issue.record("One scoped operation identifier was accepted for two operation kinds.")
    }
    #expect(await handle.close() == .closed)
    #expect(await provider.close() == .closed)
  }

  private func contribution<Model: Persistable>(
    id: String,
    schemaID: String? = nil,
    digestByte: Character,
    entity: Model.Type,
    mutationAdapter: (any DesignDatabaseRuntimeMutationAdapter)? = nil,
    physicalWriteReclaimers: [
      any DesignDatabaseRuntimePhysicalWriteReclaimer
    ] = []
  ) throws -> DesignDatabaseRuntimeContribution {
    let bindingDigest = try digest(repeating: digestByte)
    return try DesignDatabaseRuntimeContribution(
      id: DesignDatabaseRuntimeContributionID(id),
      designSchemaMember: DesignSchemaBundleMember(
        schemaID: DesignSchemaID(rawValue: schemaID ?? id),
        version: .v1,
        canonicalDigest: bindingDigest
      ),
      bindingDigest: bindingDigest,
      entities: [try Model.schemaEntity],
      entityRuntimes: [try DatabaseFrameworkRuntime.entity(Model.self)],
      mutationAdapter: mutationAdapter,
      physicalWriteReclaimers: physicalWriteReclaimers
    )
  }

  private func mutationSubmission(
    operation: String,
    payload: [UInt8],
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    schemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    dependencyGraphDigest: ContentDigest,
    targetFacet: String = "logic",
    expectedWriteCount: UInt64 = 1,
    identityPlan: DesignMutationIdentityPlan = DesignMutationIdentityPlan(),
    dependencyLockUpdate: DesignDependencyLockUpdate? = nil
  ) throws -> DesignCommitSubmission {
    let digester = SHA256ContentDigester()
    let payloadDigest = try DesignMutationPlanDigest.payload(
      payload,
      using: digester
    )
    let segment = try DesignMutationPlanSegment(
      id: DesignMutationPlanSegmentID(rawValue: targetFacet + "-import"),
      schemaID: DesignSchemaID(rawValue: "lsi.logic"),
      schemaVersion: .v1,
      adapterVersion: "1.0.0",
      targetFacet: DesignFacetID(rawValue: targetFacet),
      identityPlan: identityPlan,
      payload: payload,
      payloadDigest: payloadDigest,
      expectedWriteCount: expectedWriteCount
    )
    let budget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1_024,
      maximumPreparedWriteCount: expectedWriteCount,
      maximumValidationReadCount: 16
    )
    let evidenceDigest = try digest(repeating: "b")
    let planDigest = try DesignMutationPlanDigest.plan(
      databaseID: databaseID,
      baseRevision: baseRevision,
      designSchemaBundleDigest: schemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: dependencyGraphDigest,
      sourceEvidenceDigest: evidenceDigest,
      budget: budget,
      segments: [segment],
      dependencyLockUpdate: dependencyLockUpdate,
      using: digester
    )
    let plan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: baseRevision,
      designSchemaBundleDigest: schemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: dependencyGraphDigest,
      sourceEvidenceDigest: evidenceDigest,
      budget: budget,
      segments: [segment],
      planDigest: planDigest,
      dependencyLockUpdate: dependencyLockUpdate
    )
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    return DesignCommitSubmission(
      operationID: operationID,
      plan: plan,
      requestDigest: try DesignMutationPlanDigest.request(
        operationID: operationID,
        planDigest: planDigest,
        using: digester
      )
    )
  }

  private func dependencySubmission(
    operation: String,
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    schemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    dependencyGraphDigest: ContentDigest,
    update: DesignDependencyLockUpdate
  ) throws -> DesignCommitSubmission {
    let digester = SHA256ContentDigester()
    let budget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1,
      maximumPreparedWriteCount: 1,
      maximumValidationReadCount: 16
    )
    let evidenceDigest = try digest(repeating: "c")
    let planDigest = try DesignMutationPlanDigest.plan(
      databaseID: databaseID,
      baseRevision: baseRevision,
      designSchemaBundleDigest: schemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: dependencyGraphDigest,
      sourceEvidenceDigest: evidenceDigest,
      budget: budget,
      segments: [],
      dependencyLockUpdate: update,
      using: digester
    )
    let plan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: baseRevision,
      designSchemaBundleDigest: schemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: dependencyGraphDigest,
      sourceEvidenceDigest: evidenceDigest,
      budget: budget,
      segments: [],
      planDigest: planDigest,
      dependencyLockUpdate: update
    )
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    return DesignCommitSubmission(
      operationID: operationID,
      plan: plan,
      requestDigest: try DesignMutationPlanDigest.request(
        operationID: operationID,
        planDigest: planDigest,
        using: digester
      )
    )
  }

  private func digest(repeating character: Character) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: character, count: 64)
    )
  }

  private func makeAttachment() async throws -> (
    DesignDatabaseRuntimeAttachment,
    DesignDatabaseRuntimeRegistrationBundle,
    DesignDatabaseLocator
  ) {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["genesis-test"]
    )
    let attachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: DisabledTestContainerProvider()
    ).open(locator: locator, registration: registration)
    return (attachment, registration, locator)
  }

  private func makeMutableAttachment(
    physicalWriteReclaimers: [
      any DesignDatabaseRuntimePhysicalWriteReclaimer
    ] = [RuntimeTestPhysicalWriteReclaimer()]
  ) async throws -> (
    DesignDatabaseRuntimeAttachment,
    DesignDatabaseRuntimeRegistrationBundle,
    DesignDatabaseLocator
  ) {
    let registration = try DesignDatabaseRuntimeRegistrationBuilder().build(
      schemaVersion: Schema.Version(1, 0, 0),
      contributions: [
        try contribution(
          id: "lsi.logic",
          digestByte: "1",
          entity: RuntimeTestLogicEntity.self,
          mutationAdapter: try RuntimeTestMutationAdapter(),
          physicalWriteReclaimers: physicalWriteReclaimers
        ),
      ]
    )
    let locator = try DesignDatabaseLocator(
      namespace: "workspace",
      segments: ["mutable-collection-test"]
    )
    let attachment = try await DesignDatabaseRuntimeAttacher(
      containerProvider: DisabledTestContainerProvider()
    ).open(locator: locator, registration: registration)
    return (attachment, registration, locator)
  }

  private func genesisRequest(
    locator: DesignDatabaseLocator,
    designSchemaBundle: DesignSchemaBundle,
    registrationDigest: ContentDigest,
    operation: String,
    genesisLow: UInt64,
    capabilities: DesignCapabilitySet? = nil
  ) throws -> DesignDatabaseRuntimeGenesisRequest {
    let declaredCapabilities: DesignCapabilitySet
    if let capabilities {
      declaredCapabilities = capabilities
    } else {
      declaredCapabilities = try DesignCapabilitySet([])
    }
    return try DesignDatabaseRuntimeGenesisRequest(
      locator: locator,
      databaseID: DesignDatabaseID(high: 1, low: 2),
      genesisRevisionID: DesignRevisionID(high: 0, low: genesisLow),
      authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID(
        high: 3,
        low: 4
      ),
      operationID: DesignDatabaseOperationID(rawValue: operation),
      declaredFeatureCapabilities: declaredCapabilities,
      initialSchemaBundle: designSchemaBundle,
      registrationDigest: registrationDigest
    )
  }

  private func capabilitySet(id: String) throws -> DesignCapabilitySet {
    try DesignCapabilitySet([
      DesignCapabilityDescriptor(
        capabilityID: DesignCapabilityID(rawValue: id),
        versions: SchemaVersionRange(
          lowerBound: SchemaVersion(major: 1, minor: 0, patch: 0),
          upperBound: SchemaVersion(major: 2, minor: 0, patch: 0)
        )
      ),
    ])
  }

  private func referenceRequest(
    operation: String,
    name: DesignReferenceName,
    expectedGeneration: UInt64,
    expectedRevision: DesignRevisionReference?,
    desiredRevision: DesignRevisionReference?
  ) throws -> DesignReferenceUpdateRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let requestDigest = try DesignReferenceUpdateDigest.request(
      operationID: operationID,
      name: name,
      expectedGeneration: expectedGeneration,
      expectedRevision: expectedRevision,
      desiredRevision: desiredRevision,
      using: SHA256ContentDigester()
    )
    return DesignReferenceUpdateRequest(
      operationID: operationID,
      name: name,
      expectedGeneration: expectedGeneration,
      expectedRevision: expectedRevision,
      desiredRevision: desiredRevision,
      requestDigest: requestDigest
    )
  }

  private func retentionRequest(
    operation: String,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference
  ) throws -> DesignRevisionRetentionRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let reason = try DesignRevisionRetentionReason(rawValue: "release")
    let evidenceDigest = try digest(repeating: "d")
    let requestDigest = try DesignRevisionRetentionDigest.retainingRequest(
      operationID: operationID,
      claimID: claimID,
      revision: revision,
      reason: reason,
      evidenceDigest: evidenceDigest,
      using: SHA256ContentDigester()
    )
    return DesignRevisionRetentionRequest(
      operationID: operationID,
      claimID: claimID,
      revision: revision,
      reason: reason,
      evidenceDigest: evidenceDigest,
      requestDigest: requestDigest
    )
  }

  private func retentionReleaseRequest(
    operation: String,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    generation: UInt64
  ) throws -> DesignRevisionRetentionReleaseRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let requestDigest = try DesignRevisionRetentionDigest.releasingRequest(
      operationID: operationID,
      claimID: claimID,
      expectedRevision: revision,
      expectedGeneration: generation,
      using: SHA256ContentDigester()
    )
    return DesignRevisionRetentionReleaseRequest(
      operationID: operationID,
      claimID: claimID,
      expectedRevision: revision,
      expectedGeneration: generation,
      requestDigest: requestDigest
    )
  }

  private func commitAbandonmentRequest(
    operation: String,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest
  ) throws -> DesignCommitAbandonmentRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let reason = try DesignCommitAbandonmentReason(
      rawValue: "caller-abandoned"
    )
    let evidenceDigest = try digest(repeating: "e")
    let requestDigest = try DesignCommitAbandonmentDigest.request(
      operationID: operationID,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      using: SHA256ContentDigester()
    )
    return DesignCommitAbandonmentRequest(
      operationID: operationID,
      targetOperation: targetOperation,
      targetRequestDigest: targetRequestDigest,
      reason: reason,
      evidenceDigest: evidenceDigest,
      requestDigest: requestDigest
    )
  }
}

private struct SecurityEnabledContainerProvider:
  DesignDatabaseRuntimeContainerProviding
{
  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer {
    do {
      return try await DBContainer.inMemory(
        for: registration.schema,
        monotonicClock: RuntimeTestMonotonicClock(),
        wallClock: RuntimeTestWallClock(),
        runtimeConfiguration: registration.runtimeConfiguration,
        security: .enabled(
          adminRoles: [DesignDatabaseRuntimeStorageSecurity.administratorRole]
        )
      )
    } catch {
      throw .containerProviderFailed(reason: String(describing: error))
    }
  }
}

private struct DisabledTestContainerProvider:
  DesignDatabaseRuntimeContainerProviding
{
  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer {
    do {
      return try await DBContainer.inMemory(
        for: registration.schema,
        monotonicClock: RuntimeTestMonotonicClock(),
        wallClock: RuntimeTestWallClock(),
        runtimeConfiguration: registration.runtimeConfiguration,
        security: .disabled
      )
    } catch {
      throw .containerProviderFailed(reason: String(describing: error))
    }
  }
}

private struct ReopenableSQLiteContainerProvider:
  DesignDatabaseRuntimeContainerProviding
{
  let databasePath: String
  let security: SecurityConfiguration

  init(
    databasePath: String,
    security: SecurityConfiguration = .disabled
  ) {
    self.databasePath = databasePath
    self.security = security
  }

  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer {
    do {
      return try await DBContainer.sqlite(
        for: registration.schema,
        path: databasePath,
        monotonicClock: RuntimeTestMonotonicClock(),
        wallClock: RuntimeTestWallClock(),
        runtimeConfiguration: registration.runtimeConfiguration,
        security: security
      )
    } catch {
      throw .containerProviderFailed(reason: String(describing: error))
    }
  }
}

private struct MissingRuntimeStorageRoleContainerProvider:
  DesignDatabaseRuntimeContainerProviding
{
  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer {
    do {
      return try await DBContainer.inMemory(
        for: registration.schema,
        monotonicClock: RuntimeTestMonotonicClock(),
        wallClock: RuntimeTestWallClock(),
        runtimeConfiguration: registration.runtimeConfiguration,
        security: .enabled(adminRoles: ["unrelated-storage-role"])
      )
    } catch {
      throw .containerProviderFailed(reason: String(describing: error))
    }
  }
}

private struct MismatchingContainerProvider: DesignDatabaseRuntimeContainerProviding {
  func openContainer(
    for locator: DesignDatabaseLocator,
    registration: DesignDatabaseRuntimeRegistrationBundle
  ) async throws(DesignDatabaseRuntimeError) -> DBContainer {
    do {
      let schema = try Schema(
        entities: [try RuntimeTestLayoutEntity.schemaEntity],
        version: Schema.Version(1, 0, 0)
      )
      let runtime = try DatabaseFrameworkRuntime.configuration(
        entityRuntimes: [
          try DatabaseFrameworkRuntime.entity(RuntimeTestLayoutEntity.self),
        ]
      )
      return try await DBContainer.inMemory(
        for: schema,
        monotonicClock: RuntimeTestMonotonicClock(),
        wallClock: RuntimeTestWallClock(),
        runtimeConfiguration: runtime,
        security: .disabled
      )
    } catch {
      throw .containerProviderFailed(reason: String(describing: error))
    }
  }
}

private struct RuntimeTestMonotonicClock: StorageMonotonicClock {
  private let clock = ContinuousClock()
  private let origin: ContinuousClock.Instant

  init() {
    origin = clock.now
  }

  var now: StorageInstant {
    StorageInstant(durationSinceReference: origin.duration(to: clock.now))
  }

  func sleep(
    until deadline: StorageInstant
  ) async throws(StorageClockError) {
    let delay = now.duration(to: deadline)
    guard delay > .zero else { return }
    do {
      try await Task.sleep(for: delay)
    } catch is CancellationError {
      throw .cancelled
    } catch {
      throw .unavailable
    }
  }
}

private struct RuntimeTestWallClock: WallClock {
  var now: Timestamp {
    Timestamp(secondsSinceUnixEpoch: 1_700_000_000)
  }
}

private struct AllowingRuntimeTestAuthorizer: DesignDatabaseAuthorizing {
  func authorizeRequestedGrants(
    _ requestedGrants: DesignDatabaseAuthorizationGrantSet,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError) -> DesignDatabaseAuthorizationGrantSet {
    requestedGrants
  }

  func authorize(
    _ grant: DesignDatabaseAuthorizationGrant,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError) {}
}

private struct StorageRoleRejectingRuntimeTestAuthorizer:
  DesignDatabaseAuthorizing
{
  func authorizeRequestedGrants(
    _ requestedGrants: DesignDatabaseAuthorizationGrantSet,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError) -> DesignDatabaseAuthorizationGrantSet {
    try requireUnprivilegedContext()
    return requestedGrants
  }

  func authorize(
    _ grant: DesignDatabaseAuthorizationGrant,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) async throws(DesignDatabaseError) {
    try requireUnprivilegedContext()
  }

  private func requireUnprivilegedContext() throws(DesignDatabaseError) {
    guard RequestAuthorization.context.principal?.roles.contains(
      DesignDatabaseRuntimeStorageSecurity.administratorRole
    ) != true else {
      throw .corruption(
        "The public authorizer inherited the internal Runtime storage role."
      )
    }
  }
}
