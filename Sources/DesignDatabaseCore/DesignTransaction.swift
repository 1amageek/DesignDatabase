import CircuiteFoundation

public struct DesignTransaction: ~Copyable {
  public let baseRevision: DesignRevisionReference

  private let databaseID: DesignDatabaseID
  private let schemas: [DesignFacetID: DesignFacetSchema]
  private let baseEntities: [DesignEntityID: DesignEntityRecord]
  private var entities: [DesignEntityID: DesignEntityRecord]
  private var nextEntityValue: UInt64
  private var changes: [DesignEntityChange]

  package init(
    baseRevision: DesignRevisionReference,
    schemas: [DesignFacetID: DesignFacetSchema],
    entities: [DesignEntityID: DesignEntityRecord],
    nextEntityValue: UInt64
  ) {
    self.baseRevision = baseRevision
    self.databaseID = baseRevision.databaseID
    self.schemas = schemas
    self.baseEntities = entities
    self.entities = entities
    self.nextEntityValue = nextEntityValue
    self.changes = []
  }

  public mutating func createEntity(
    facet: DesignFacetID,
    kind: DesignEntityKindID
  ) throws(DesignDatabaseError) -> DesignEntityID {
    guard let facetSchema = schemas[facet] else { throw .unknownFacet(facet) }
    guard facetSchema.entities.contains(where: { $0.kindID == kind }) else {
      throw .unknownEntityKind(facet: facet, kind: kind)
    }
    guard nextEntityValue < UInt64.max else {
      throw .resourceExhausted(limit: UInt64.max, requested: UInt64.max)
    }
    nextEntityValue += 1
    let identifier: DesignEntityID
    do {
      identifier = try DesignEntityID(rawValue: nextEntityValue)
    } catch {
      throw .corruption("Entity identifier allocator produced zero.")
    }
    let key = DesignEntityKey(databaseID: databaseID, entityID: identifier)
    entities[identifier] = DesignEntityRecord(key: key, facetID: facet, kindID: kind)
    changes.append(.created(identifier))
    return identifier
  }

  public mutating func deleteEntity(_ key: DesignEntityKey) throws(DesignDatabaseError) {
    try validateDatabase(key)
    guard entities.removeValue(forKey: key.entityID) != nil else { throw .entityNotFound(key) }
    changes.append(.deleted(key.entityID))
  }

  public mutating func setField(
    entity key: DesignEntityKey,
    field: DesignFieldID,
    value: DesignValue?
  ) throws(DesignDatabaseError) {
    try validateDatabase(key)
    guard var record = entities[key.entityID] else { throw .entityNotFound(key) }
    guard let schema = entitySchema(for: record),
      let fieldSchema = schema.fields.first(where: { $0.id == field })
    else {
      throw .unknownField(field)
    }
    if let value, !fieldSchema.valueKind.accepts(value) {
      throw .invalidQuery("Value type does not match field \(field.rawValue).")
    }
    record.fields[field] = value
    entities[key.entityID] = record
    changes.append(.fieldChanged(entity: key.entityID, field: field))
  }

  public mutating func replaceRelation(
    entity key: DesignEntityKey,
    relation: DesignRelationKindID,
    targets: Set<DesignEntityID>
  ) throws(DesignDatabaseError) {
    try validateDatabase(key)
    guard var record = entities[key.entityID] else { throw .entityNotFound(key) }
    guard entitySchema(for: record)?.relations.contains(where: { $0.id == relation }) == true else {
      throw .unknownRelation(relation)
    }
    record.relations[relation] = targets
    entities[key.entityID] = record
    changes.append(.relationChanged(entity: key.entityID, relation: relation))
  }

  public mutating func replaceSpatialEntries(
    entity key: DesignEntityKey,
    entries: [DesignSpatialEntry]
  ) throws(DesignDatabaseError) {
    try validateDatabase(key)
    guard var record = entities[key.entityID] else { throw .entityNotFound(key) }
    guard schemas[record.facetID]?.indexes.contains(.spatial) == true else {
      throw .requiredIndexUnavailable(.spatial)
    }
    record.spatialEntries = entries
    entities[key.entityID] = record
    changes.append(.spatialChanged(key.entityID))
  }

  public mutating func apply(_ batch: DesignMutationBatch) throws(DesignDatabaseError) {
    for mutation in batch.mutations {
      switch mutation {
      case .create(let facet, let kind, let requestedID):
        guard requestedID == nil else {
          throw .invalidQuery("Caller-assigned entity IDs are not supported by the native allocator.")
        }
        _ = try createEntity(facet: facet, kind: kind)
      case .delete(let key): try deleteEntity(key)
      case .setField(let key, let field, let value):
        try setField(entity: key, field: field, value: value)
      case .replaceRelation(let key, let relation, let targets):
        try replaceRelation(entity: key, relation: relation, targets: targets)
      case .replaceSpatialEntries(let key, let entries):
        try replaceSpatialEntries(entity: key, entries: entries)
      }
    }
  }

  public func resolve(_ key: DesignEntityKey) throws(DesignDatabaseError) -> DesignEntityRecord {
    try validateDatabase(key)
    guard let record = entities[key.entityID] else { throw .entityNotFound(key) }
    return record
  }

  package consuming func finalized() throws(DesignDatabaseError) -> DesignTransactionState {
    try validateFinalState()
    return DesignTransactionState(
      baseEntities: baseEntities,
      entities: entities,
      changes: changes,
      nextEntityValue: nextEntityValue
    )
  }

  private func validateDatabase(_ key: DesignEntityKey) throws(DesignDatabaseError) {
    guard key.databaseID == databaseID else {
      throw .crossDatabaseReference(expected: databaseID, actual: key.databaseID)
    }
  }

  private func entitySchema(for record: DesignEntityRecord) -> DesignEntitySchema? {
    schemas[record.facetID]?.entities.first { $0.kindID == record.kindID }
  }

  private func validateFinalState() throws(DesignDatabaseError) {
    for record in entities.values.sorted(by: { $0.key.entityID < $1.key.entityID }) {
      guard let schema = entitySchema(for: record) else {
        throw .unknownEntityKind(facet: record.facetID, kind: record.kindID)
      }
      for field in schema.fields where field.isRequired && record.fields[field.id] == nil {
        throw .missingRequiredField(entity: record.key.entityID, field: field.id)
      }
      for value in record.fields.values {
        switch value {
        case .real(let number) where !number.isFinite:
          throw .invalidQuery("Real field values must be finite.")
        case .entity(let target):
          try validateDatabase(target)
          guard entities[target.entityID] != nil else {
            throw .entityNotFound(target)
          }
        default:
          break
        }
      }
      for relation in schema.relations {
        for target in record.relations[relation.id] ?? [] {
          guard let targetRecord = entities[target] else {
            throw .relationTargetMissing(source: record.key.entityID, target: target)
          }
          if
            !relation.targetFacets.isEmpty,
            !relation.targetFacets.contains(targetRecord.facetID),
            let expectedFacet = relation.targetFacets.min(by: { $0.rawValue < $1.rawValue })
          {
            throw .facetMismatch(
              entity: target,
              expected: expectedFacet,
              actual: targetRecord.facetID
            )
          }
        }
      }
    }
    try validateUniqueConstraints()
  }

  private func validateUniqueConstraints() throws(DesignDatabaseError) {
    for facetSchema in schemas.values.sorted(by: { $0.facetID.rawValue < $1.facetID.rawValue }) {
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
              throw .uniquenessViolation(
                facet: facetSchema.facetID,
                kind: entitySchema.kindID,
                constraint: constraint.id,
                first: first,
                second: record.key
              )
            }
            owners[values] = record.key
          }
        }
      }
    }
  }
}
