import CircuiteFoundation

public struct DesignReferenceReadSnapshot: Sendable {
  public let revision: DesignRevisionReference
  public let stateDigest: ContentDigest
  public let schemas: [DesignSchemaDescriptor]

  private let facetSchemas: [DesignFacetID: DesignFacetSchema]
  private let entities: [DesignEntityID: DesignEntityRecord]
  private let changesByBase: [DesignRevisionReference: DesignChangeSet]
  private let entitiesByFacet: [DesignFacetID: Set<DesignEntityID>]
  private let entitiesByKind: [DesignFacetID: [DesignEntityKindID: Set<DesignEntityID>]]
  private let entitiesByName: [DesignNameIndexKey: Set<DesignEntityID>]
  private let hierarchyChildren: [DesignEntityID: Set<DesignEntityID>]
  private let connectivityAdjacency: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]]
  private let connectivityRelations: Set<DesignRelationKindID>
  private let crossFacetAdjacency: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]]
  private let crossFacetRelations: Set<DesignRelationKindID>
  private let dependencySources: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]]
  private let dependencyRelations: Set<DesignRelationKindID>
  private let spatialRecords: [DesignEntityID: [DesignSpatialIndexRecord]]

  package init(
    revision: DesignRevisionReference,
    stateDigest: ContentDigest,
    facetSchemas: [DesignFacetID: DesignFacetSchema],
    entities: [DesignEntityID: DesignEntityRecord],
    changesByBase: [DesignRevisionReference: DesignChangeSet]
  ) {
    self.revision = revision
    self.stateDigest = stateDigest
    self.schemas = facetSchemas.values.map { $0.descriptor }.sorted {
      $0.schemaID < $1.schemaID
    }
    self.facetSchemas = facetSchemas
    self.entities = entities
    self.changesByBase = changesByBase

    var entitiesByFacet: [DesignFacetID: Set<DesignEntityID>] = [:]
    var entitiesByKind: [DesignFacetID: [DesignEntityKindID: Set<DesignEntityID>]] = [:]
    var entitiesByName: [DesignNameIndexKey: Set<DesignEntityID>] = [:]
    var hierarchyChildren: [DesignEntityID: Set<DesignEntityID>] = [:]
    var connectivityAdjacency: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]] = [:]
    var connectivityRelations = Set<DesignRelationKindID>()
    var crossFacetAdjacency: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]] = [:]
    var crossFacetRelations = Set<DesignRelationKindID>()
    var dependencySources: [DesignRelationKindID: [DesignEntityID: Set<DesignEntityID>]] = [:]
    var dependencyRelations = Set<DesignRelationKindID>()
    var spatialRecords: [DesignEntityID: [DesignSpatialIndexRecord]] = [:]

    for record in entities.values {
      entitiesByFacet[record.facetID, default: []].insert(record.key.entityID)
      entitiesByKind[record.facetID, default: [:]][record.kindID, default: []]
        .insert(record.key.entityID)

      let relationSchemas = facetSchemas[record.facetID]?.entities.first {
        $0.kindID == record.kindID
      }?.relations ?? []
      let fieldSchemas = facetSchemas[record.facetID]?.entities.first {
        $0.kindID == record.kindID
      }?.fields ?? []
      for fieldSchema in fieldSchemas where fieldSchema.isNameIndexSource {
        guard case .string(let value) = record.fields[fieldSchema.id] else { continue }
        entitiesByName[
          DesignNameIndexKey(
            facetID: record.facetID,
            fieldID: fieldSchema.id,
            value: value
          ),
          default: []
        ].insert(record.key.entityID)
      }
      for relationSchema in relationSchemas {
        let targets = record.relations[relationSchema.id] ?? []
        if relationSchema.isHierarchyParent {
          for target in targets {
            hierarchyChildren[target, default: []].insert(record.key.entityID)
          }
        }
        if relationSchema.isConnectivity {
          connectivityRelations.insert(relationSchema.id)
          for target in targets {
            connectivityAdjacency[relationSchema.id, default: [:]][target, default: []]
              .insert(record.key.entityID)
            connectivityAdjacency[relationSchema.id, default: [:]][record.key.entityID, default: []]
              .insert(target)
          }
        }
        if relationSchema.isCrossFacet {
          crossFacetRelations.insert(relationSchema.id)
          for target in targets {
            crossFacetAdjacency[relationSchema.id, default: [:]][target, default: []]
              .insert(record.key.entityID)
            crossFacetAdjacency[relationSchema.id, default: [:]][record.key.entityID, default: []]
              .insert(target)
          }
        }
        if relationSchema.isDependency {
          dependencyRelations.insert(relationSchema.id)
          for target in targets {
            dependencySources[relationSchema.id, default: [:]][target, default: []]
              .insert(record.key.entityID)
          }
        }
      }

      for entry in record.spatialEntries {
        spatialRecords[entry.container, default: []].append(
          DesignSpatialIndexRecord(
            entityID: record.key.entityID,
            layer: entry.layer,
            bounds: entry.bounds
          )
        )
      }
    }

    self.entitiesByFacet = entitiesByFacet
    self.entitiesByKind = entitiesByKind
    self.entitiesByName = entitiesByName
    self.hierarchyChildren = hierarchyChildren
    self.connectivityAdjacency = connectivityAdjacency
    self.connectivityRelations = connectivityRelations
    self.crossFacetAdjacency = crossFacetAdjacency
    self.crossFacetRelations = crossFacetRelations
    self.dependencySources = dependencySources
    self.dependencyRelations = dependencyRelations
    self.spatialRecords = spatialRecords
  }

  public func resolve(
    _ reference: DesignEntityReference
  ) throws(DesignDatabaseError) -> DesignEntityRecord {
    guard reference.revision.databaseID == revision.databaseID else {
      throw .crossDatabaseReference(
        expected: revision.databaseID,
        actual: reference.revision.databaseID
      )
    }
    guard reference.revision == revision else {
      throw .revisionNotFound(reference.revision)
    }
    let key = DesignEntityKey(databaseID: revision.databaseID, entityID: reference.entityID)
    guard let record = entities[reference.entityID] else {
      throw .entityNotFound(key)
    }
    guard record.facetID == reference.facetID else {
      throw .facetMismatch(
        entity: reference.entityID,
        expected: reference.facetID,
        actual: record.facetID
      )
    }
    guard record.kindID == reference.kindID else {
      throw .kindMismatch(
        entity: reference.entityID,
        expected: reference.kindID,
        actual: record.kindID
      )
    }
    return record
  }

  public func entity(_ key: DesignEntityKey) throws(DesignDatabaseError) -> DesignEntityRecord {
    guard key.databaseID == revision.databaseID else {
      throw .crossDatabaseReference(expected: revision.databaseID, actual: key.databaseID)
    }
    guard let record = entities[key.entityID] else {
      throw .entityNotFound(key)
    }
    return record
  }

  public func facetSchema(
    _ facetID: DesignFacetID
  ) throws(DesignDatabaseError) -> DesignFacetSchema {
    guard let schema = facetSchemas[facetID] else { throw .unknownFacet(facetID) }
    return schema
  }

  public func changes(
    since base: DesignRevisionReference
  ) throws(DesignDatabaseError) -> DesignChangeSet {
    guard base.databaseID == revision.databaseID else {
      throw .crossDatabaseReference(expected: revision.databaseID, actual: base.databaseID)
    }
    guard let changes = changesByBase[base] else {
      throw .revisionNotFound(base)
    }
    return changes
  }

  public func execute(_ query: DesignQuery) throws(DesignDatabaseError) -> DesignQueryResult {
    if Task.isCancelled { throw .cancelled }
    let plan = try plan(query.source, policy: query.executionPolicy)
    var records = try candidates(for: query.source, plan: plan)
    if let predicate = query.predicate {
      records = records.filter { matches(predicate, record: $0) }
    }
    records.sort {
      switch query.ordering {
      case .entityIDAscending: return $0.key.entityID < $1.key.entityID
      case .entityIDDescending: return $1.key.entityID < $0.key.entityID
      }
    }

    let requestedLimit = query.limit ?? query.executionPolicy.maximumResultCount
    let effectiveLimit = min(requestedLimit, query.executionPolicy.maximumResultCount)
    if UInt64(records.count) > query.executionPolicy.maximumResultCount, query.limit == nil {
      throw .resourceExhausted(
        limit: query.executionPolicy.maximumResultCount,
        requested: UInt64(records.count)
      )
    }
    if UInt64(records.count) > effectiveLimit {
      records.removeLast(records.count - Int(effectiveLimit))
    }

    return DesignQueryResult(
      records: records,
      explain: DesignQueryExplain(
        selectedIndex: plan.index,
        estimatedScanCount: plan.estimatedCount,
        admittedFullScan: plan.fullScan,
        ordering: query.ordering
      )
    )
  }

  private func plan(
    _ source: DesignQuerySource,
    policy: DesignQueryExecutionPolicy
  ) throws(DesignDatabaseError) -> (index: DesignIndexKind, estimatedCount: UInt64, fullScan: Bool) {
    if case .connected(_, let relations) = source,
      !relations.isSubset(of: connectivityRelations)
    {
      throw .invalidQuery("Connectivity query contains a relation not declared as connectivity.")
    }
    if case .crossFacet(_, let relations) = source,
      !relations.isSubset(of: crossFacetRelations)
    {
      throw .invalidQuery("Cross-facet query contains a relation not declared as cross-facet.")
    }
    if case .dependents(_, let relations) = source,
      !relations.isSubset(of: dependencyRelations)
    {
      throw .invalidQuery("Dependency query contains a relation not declared as dependency.")
    }
    if case .name(let facet, let kind, let field, _) = source {
      guard let facetSchema = facetSchemas[facet] else { throw .unknownFacet(facet) }
      let eligible = facetSchema.entities.contains { entity in
        (kind == nil || entity.kindID == kind)
          && entity.fields.contains { $0.id == field && $0.isNameIndexSource }
      }
      guard eligible else {
        throw .invalidQuery("Name query field is not declared as a name index source.")
      }
    }
    let required: DesignIndexKind
    switch source {
    case .entities: required = .entity
    case .facet: required = .facet
    case .name: required = .name
    case .hierarchyChildren: required = .hierarchy
    case .connected: required = .connectivity
    case .crossFacet: required = .crossFacet
    case .dependents: required = .dependency
    case .spatial: required = .spatial
    case .changed: required = .change
    }
    let available: Bool
    if case .name(let facet, _, _, _) = source {
      available = facetSchemas[facet]?.indexes.contains(.name) == true
    } else {
      available = required == .entity || required == .facet || required == .change
        || facetSchemas.values.contains { $0.indexes.contains(required) }
    }
    if !available && !policy.allowsFullScan {
      throw .requiredIndexUnavailable(required)
    }
    let fullScan = !available
    return (
      required,
      estimatedCount(for: source, usingFullScan: fullScan),
      fullScan
    )
  }

  private func candidates(
    for source: DesignQuerySource,
    plan: (index: DesignIndexKind, estimatedCount: UInt64, fullScan: Bool)
  ) throws(DesignDatabaseError) -> [DesignEntityRecord] {
    if plan.fullScan {
      return try fullScanCandidates(for: source)
    }
    switch source {
    case .entities(let identifiers):
      return identifiers.compactMap { entities[$0] }
    case .facet(let facet, let kind):
      let identifiers = kind.map { entitiesByKind[facet]?[$0] ?? [] }
        ?? entitiesByFacet[facet, default: []]
      return identifiers.compactMap { entities[$0] }
    case .name(let facet, let kind, let field, let value):
      var identifiers = entitiesByName[
        DesignNameIndexKey(facetID: facet, fieldID: field, value: value),
        default: []
      ]
      if let kind {
        identifiers.formIntersection(entitiesByKind[facet]?[kind] ?? [])
      }
      return identifiers.compactMap { entities[$0] }
    case .hierarchyChildren(let parent):
      return hierarchyChildren[parent, default: []].compactMap { entities[$0] }
    case .connected(let start, let relationKinds):
      var identifiers = start
      for relation in relationKinds {
        for target in start {
          identifiers.formUnion(connectivityAdjacency[relation]?[target] ?? [])
        }
      }
      return identifiers.compactMap { entities[$0] }
    case .crossFacet(let start, let relationKinds):
      var identifiers = Set<DesignEntityID>()
      for relation in relationKinds {
        for entity in start {
          identifiers.formUnion(crossFacetAdjacency[relation]?[entity] ?? [])
        }
      }
      return identifiers.compactMap { entities[$0] }
    case .dependents(let dependencies, let relationKinds):
      var identifiers = Set<DesignEntityID>()
      for relation in relationKinds {
        for dependency in dependencies {
          identifiers.formUnion(dependencySources[relation]?[dependency] ?? [])
        }
      }
      return identifiers.compactMap { entities[$0] }
    case .spatial(let container, let layer, let bounds, let relation):
      let identifiers: Set<DesignEntityID> = Set(
        spatialRecords[container, default: []].compactMap { entry -> DesignEntityID? in
        guard layer == nil || entry.layer == layer else { return nil }
        switch relation {
          case .intersects: return entry.bounds.intersects(bounds) ? entry.entityID : nil
          case .containedByQuery: return bounds.contains(entry.bounds) ? entry.entityID : nil
          case .containsQuery: return entry.bounds.contains(bounds) ? entry.entityID : nil
        }
      })
      return identifiers.compactMap { entities[$0] }
    case .changed(let base):
      let changes = try self.changes(since: base)
      let identifiers = Set(changes.changes.map(entityID))
      return identifiers.compactMap { entities[$0] }
    }
  }

  private func fullScanCandidates(
    for source: DesignQuerySource
  ) throws(DesignDatabaseError) -> [DesignEntityRecord] {
    switch source {
    case .entities(let identifiers):
      return identifiers.compactMap { entities[$0] }
    case .facet(let facet, let kind):
      return entities.values.filter { record in
        record.facetID == facet && (kind == nil || record.kindID == kind)
      }
    case .name(let facet, let kind, let field, let value):
      return entities.values.filter { record in
        guard record.facetID == facet, kind == nil || record.kindID == kind else { return false }
        return record.fields[field] == .string(value)
      }
    case .hierarchyChildren(let parent):
      return entities.values.filter { record in
        relationSchemas(for: record).contains { schema in
          schema.isHierarchyParent && record.relations[schema.id]?.contains(parent) == true
        }
      }
    case .connected(let start, let relationKinds):
      return entities.values.filter { record in
        relationKinds.contains { relation in
          guard let targets = record.relations[relation] else { return false }
          return !targets.isDisjoint(with: start)
        } || start.contains(record.key.entityID)
          || start.contains { startID in
            relationKinds.contains { relation in
              entities[startID]?.relations[relation]?.contains(record.key.entityID) == true
            }
          }
      }
    case .crossFacet(let start, let relationKinds):
      return entities.values.filter { record in
        !start.contains(record.key.entityID) && (
          relationKinds.contains { relation in
            record.relations[relation]?.isDisjoint(with: start) == false
          }
            || start.contains { startID in
              relationKinds.contains { relation in
                entities[startID]?.relations[relation]?.contains(record.key.entityID) == true
              }
            }
        )
      }
    case .dependents(let dependencies, let relationKinds):
      return entities.values.filter { record in
        relationKinds.contains { relation in
          record.relations[relation]?.isDisjoint(with: dependencies) == false
        }
      }
    case .spatial(let container, let layer, let bounds, let relation):
      return entities.values.filter { record in
        record.spatialEntries.contains { entry in
          guard entry.container == container, layer == nil || entry.layer == layer else {
            return false
          }
          switch relation {
          case .intersects: return entry.bounds.intersects(bounds)
          case .containedByQuery: return bounds.contains(entry.bounds)
          case .containsQuery: return entry.bounds.contains(bounds)
          }
        }
      }
    case .changed(let base):
      let changes = try self.changes(since: base)
      let identifiers = Set(changes.changes.map(entityID))
      return identifiers.compactMap { entities[$0] }
    }
  }

  private func estimatedCount(
    for source: DesignQuerySource,
    usingFullScan: Bool
  ) -> UInt64 {
    guard !usingFullScan else { return UInt64(entities.count) }
    switch source {
    case .entities(let identifiers):
      return UInt64(identifiers.count)
    case .facet(let facet, let kind):
      return UInt64(
        kind.map { entitiesByKind[facet]?[$0]?.count ?? 0 }
          ?? entitiesByFacet[facet]?.count
          ?? 0
      )
    case .name(let facet, let kind, let field, let value):
      var identifiers = entitiesByName[
        DesignNameIndexKey(facetID: facet, fieldID: field, value: value),
        default: []
      ]
      if let kind {
        identifiers.formIntersection(entitiesByKind[facet]?[kind] ?? [])
      }
      return UInt64(identifiers.count)
    case .hierarchyChildren(let parent):
      return UInt64(hierarchyChildren[parent]?.count ?? 0)
    case .connected(let start, let relations):
      var identifiers = start
      for relation in relations {
        for target in start {
          identifiers.formUnion(connectivityAdjacency[relation]?[target] ?? [])
        }
      }
      return UInt64(identifiers.count)
    case .crossFacet(let start, let relations):
      var identifiers = Set<DesignEntityID>()
      for relation in relations {
        for entity in start {
          identifiers.formUnion(crossFacetAdjacency[relation]?[entity] ?? [])
        }
      }
      return UInt64(identifiers.count)
    case .dependents(let dependencies, let relations):
      var identifiers = Set<DesignEntityID>()
      for relation in relations {
        for dependency in dependencies {
          identifiers.formUnion(dependencySources[relation]?[dependency] ?? [])
        }
      }
      return UInt64(identifiers.count)
    case .spatial(let container, let layer, _, _):
      return UInt64(
        spatialRecords[container, default: []].count { layer == nil || $0.layer == layer }
      )
    case .changed(let base):
      return UInt64(changesByBase[base]?.changes.count ?? 0)
    }
  }

  private func relationSchemas(for record: DesignEntityRecord) -> [DesignRelationSchema] {
    facetSchemas[record.facetID]?.entities.first { $0.kindID == record.kindID }?.relations ?? []
  }

  private func matches(_ predicate: DesignPredicate, record: DesignEntityRecord) -> Bool {
    switch predicate {
    case .fieldEquals(let field, let value): return record.fields[field] == value
    case .hasRelation(let relation, let target):
      guard let values = record.relations[relation] else { return false }
      return target.map(values.contains) ?? !values.isEmpty
    case .and(let predicates): return predicates.allSatisfy { matches($0, record: record) }
    case .or(let predicates): return predicates.contains { matches($0, record: record) }
    case .not(let predicate): return !matches(predicate, record: record)
    }
  }

  private func entityID(for change: DesignEntityChange) -> DesignEntityID {
    switch change {
    case .created(let id), .deleted(let id), .spatialChanged(let id): return id
    case .fieldChanged(let id, _), .relationChanged(let id, _): return id
    }
  }
}
