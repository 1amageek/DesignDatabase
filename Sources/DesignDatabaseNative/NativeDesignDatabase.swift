import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public actor NativeDesignDatabase: DesignDatabase {
  public nonisolated let databaseID: DesignDatabaseID
  public nonisolated let capabilities: DesignCapabilitySet

  private let schemas: [DesignFacetID: DesignFacetSchema]
  private let validators: [DesignFacetID: any DesignFacetValidating]
  private let persistence: (any DesignDatabasePersisting)?
  private let digester: any ContentDigesting
  private let identifierGenerator: RandomDesignIdentifierGenerator
  private var revisions: [DesignRevisionID: DesignStoredRevision]
  private var references: [DesignReferenceName: DesignRevisionReference]
  private var nextEntityValue: UInt64
  private var snapshotCache: [DesignRevisionID: DesignReadSnapshot]
  private var isClosed: Bool
  private var isPublishing: Bool

  public init(
    request: DesignDatabaseCreateRequest,
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
    let manifest = DesignRevisionManifest(
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
      createdAt: Date()
    )
    self.databaseID = databaseID
    self.capabilities = request.capabilities
    self.schemas = schemas
    self.validators = validators
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.revisions = [
      revisionID: DesignStoredRevision(manifest: manifest, entities: [:], changeSet: changeSet)
    ]
    self.references = [.main: revision]
    self.nextEntityValue = 0
    self.snapshotCache = [:]
    self.isClosed = false
    self.isPublishing = false
  }

  public init(
    image: DesignDatabaseImage,
    validators: [any DesignFacetValidating],
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init()
  ) throws(DesignDatabaseError) {
    let schemas = try Self.schemaMap(image.schemas)
    self.databaseID = image.databaseID
    self.capabilities = image.capabilities
    self.schemas = schemas
    self.validators = try Self.validatorMap(validators, schemas: schemas)
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.revisions = image.revisions
    self.references = image.references
    self.nextEntityValue = image.nextEntityValue
    self.snapshotCache = [:]
    self.isClosed = false
    self.isPublishing = false
    try Self.validateImage(image, schemas: schemas, digester: digester)
  }

  public func persistInitialState() async throws(DesignDatabaseError) {
    try requireOpen()
    guard let persistence else { return }
    try await persistence.persist(image(), publishing: references[.main])
  }

  public func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference {
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
  ) async throws(DesignDatabaseError) -> DesignReadSnapshot {
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
    let snapshot = DesignReadSnapshot(
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
  ) async throws(DesignDatabaseError) -> DesignRevisionManifest {
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
    try requireOpen()
    try requireNotPublishing()
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
    let manifest = DesignRevisionManifest(
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
      createdAt: Date()
    )
    let stored = DesignStoredRevision(
      manifest: manifest,
      entities: state.entities,
      changeSet: changeSet
    )
    var proposedRevisions = revisions
    proposedRevisions[candidateID] = stored
    let proposedImage = image(
      revisions: proposedRevisions,
      references: references,
      nextEntityValue: state.nextEntityValue
    )
    try await persist(proposedImage, publishing: candidate)
    revisions = proposedRevisions
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
    try requireOpen()
    try requireNotPublishing()
    try validateDatabase(desired)
    guard revisions[desired.revisionID] != nil else { throw .revisionNotFound(desired) }
    if let expected { try validateDatabase(expected) }
    let previous = references[name]
    guard previous == expected else {
      throw .transactionConflict(expected: expected, actual: previous)
    }
    var proposedReferences = references
    proposedReferences[name] = desired
    let proposedImage = image(revisions: revisions, references: proposedReferences)
    try await persist(proposedImage, publishing: nil)
    references = proposedReferences
    return DesignReferenceUpdate(name: name, previous: previous, current: desired)
  }

  public func close() async throws(DesignDatabaseError) {
    if isClosed { return }
    try requireNotPublishing()
    if let persistence {
      try await persist(image(), publishing: nil)
      isPublishing = true
      do {
        try await persistence.close()
      } catch {
        isClosed = true
        isPublishing = false
        throw error
      }
    }
    isClosed = true
    isPublishing = false
  }

  private func persist(
    _ image: DesignDatabaseImage,
    publishing revision: DesignRevisionReference?
  ) async throws(DesignDatabaseError) {
    guard let persistence else { return }
    isPublishing = true
    do {
      try await persistence.persist(image, publishing: revision)
      isPublishing = false
    } catch {
      isPublishing = false
      throw error
    }
  }

  private func image(
    revisions: [DesignRevisionID: DesignStoredRevision]? = nil,
    references: [DesignReferenceName: DesignRevisionReference]? = nil,
    nextEntityValue: UInt64? = nil
  ) -> DesignDatabaseImage {
    DesignDatabaseImage(
      databaseID: databaseID,
      schemas: schemas.values.sorted { $0.facetID.rawValue < $1.facetID.rawValue },
      capabilities: capabilities,
      revisions: revisions ?? self.revisions,
      references: references ?? self.references,
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

  private func requireNotPublishing() throws(DesignDatabaseError) {
    if isPublishing { throw .persistence("Another publication is in progress.") }
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
