import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import DesignDatabaseCore
@testable import DesignDatabaseNative
import Foundation
import Testing

@Suite
struct NativeDesignDatabaseTests {
  @Test
  func transactionProducesExactImmutableCandidateAndCASPromotion() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))
    let options = try DesignTransactionOptions()

    let transaction = try await database.withTransaction(from: root, options: options) {
      (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> DesignEntityID in
      let entity = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let key = DesignEntityKey(databaseID: root.databaseID, entityID: entity)
      try transaction.setField(entity: key, field: fixture.nameField, value: .string("top"))
      return entity
    }

    #expect(transaction.candidateRevision != root)
    #expect(transaction.changes.changes == [.created(transaction.value)])
    #expect(try await database.resolve(.named(.main)) == root)
    let candidateSnapshot = try await database.snapshot(at: transaction.candidateRevision)
    let reference = DesignEntityReference(
      revision: transaction.candidateRevision,
      facetID: fixture.facet,
      kindID: fixture.kind,
      entityID: transaction.value
    )
    #expect(try candidateSnapshot.resolve(reference).fields[fixture.nameField] == .string("top"))
    let rootSnapshot = try await database.snapshot(at: root)
    #expect(throws: DesignDatabaseError.self) {
      _ = try rootSnapshot.entity(
        DesignEntityKey(databaseID: root.databaseID, entityID: transaction.value)
      )
    }

    let update = try await database.compareAndSetReference(
      .main,
      expected: root,
      desired: transaction.candidateRevision
    )
    #expect(update.previous == root)
    #expect(try await database.resolve(.named(.main)) == transaction.candidateRevision)
    try await database.close()
  }

  @Test
  func requiredFieldFailurePublishesNoRevision() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await database.withTransaction(
        from: root,
        options: try DesignTransactionOptions()
      ) { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> DesignEntityID in
        try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      }
    }
    #expect(try await database.resolve(.named(.main)) == root)
    try await database.close()
  }

  @Test
  func uniqueConstraintRejectsDuplicateCompositeKeyWithoutPublishing() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await database.withTransaction(
        from: root,
        options: try DesignTransactionOptions()
      ) { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> Void in
        for _ in 0..<2 {
          let entity = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
          try transaction.setField(
            entity: DesignEntityKey(databaseID: root.databaseID, entityID: entity),
            field: fixture.nameField,
            value: .string("duplicate")
          )
        }
      }
    }
    #expect(try await database.resolve(.named(.main)) == root)
    try await database.close()
  }

  @Test
  func reopenRejectsPersistedUniqueConstraintViolation() throws {
    let fixture = try makeFixture()
    let databaseID = try DesignDatabaseID(high: 1, low: 1)
    let revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 1, low: 1)
    )
    let firstID = try DesignEntityID(rawValue: 1)
    let secondID = try DesignEntityID(rawValue: 2)
    let records = Dictionary(uniqueKeysWithValues: [firstID, secondID].map { entityID in
      (
        entityID,
        DesignEntityRecord(
          key: DesignEntityKey(databaseID: databaseID, entityID: entityID),
          facetID: fixture.facet,
          kindID: fixture.kind,
          fields: [fixture.nameField: .string("duplicate")]
        )
      )
    })
    let digester = SHA256ContentDigester()
    let changes = [DesignEntityChange.created(firstID), .created(secondID)]
    let stateDigest = try CanonicalDesignEncoder.stateDigest(entities: records, using: digester)
    let changeDigest = try CanonicalDesignEncoder.changeDigest(changes: changes, using: digester)
    let changeSet = DesignChangeSet(
      baseRevision: revision,
      targetRevision: revision,
      changes: changes,
      digest: changeDigest
    )
    let schemaDigests = Dictionary(uniqueKeysWithValues: fixture.request.schemas.map {
      ($0.descriptor.schemaID, $0.descriptor.canonicalDigest)
    })
    let manifest = DesignReferenceRevisionManifest(
      revision: revision,
      parents: [],
      stateDigest: stateDigest,
      schemaDigests: schemaDigests,
      changeSetDigest: changeDigest,
      provenance: nil,
      createdAt: try ExecutionTimestamp(Date(timeIntervalSince1970: 1))
    )
    let image = DesignDatabaseImage(
      databaseID: databaseID,
      schemas: fixture.request.schemas,
      capabilities: fixture.request.capabilities,
      revisions: [
        revision.revisionID: DesignStoredRevision(
          manifest: manifest,
          entities: records,
          changeSet: changeSet
        )
      ],
      references: [.main: revision],
      nextEntityValue: 2
    )

    #expect(throws: DesignDatabaseError.self) {
      let authorization = try makeAuthorization()
      _ = try NativeDesignDatabase(
        image: image,
        validators: [],
        authorizationSubjectScopeID: authorization.subjectScopeID,
        authorizationGrants: authorization.grants,
        authorizer: authorization.authority
      )
    }
  }

  @Test
  func transactionManifestScopesProvenanceToBaseAndCandidate() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))
    let instant = Date(timeIntervalSince1970: 1)
    let source = try ExecutionProvenance(
      producer: ProducerIdentity(kind: .engine, identifier: "test.engine", version: "1"),
      startedAt: instant,
      completedAt: instant
    )
    let result = try await database.withTransaction(
      from: root,
      options: try DesignTransactionOptions(provenance: source)
    ) { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> DesignEntityID in
      let entity = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      try transaction.setField(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: entity),
        field: fixture.nameField,
        value: .string("scoped")
      )
      return entity
    }
    let manifest = try await database.manifest(at: result.candidateRevision)

    #expect(manifest.provenance?.inputDesignRevision == root)
    #expect(manifest.provenance?.outputDesignRevision == result.candidateRevision)
    try await database.close()
  }

  @Test
  func indexedSpatialQueryReportsPlanAndFindsRecord() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))
    let result = try await database.withTransaction(
      from: root,
      options: try DesignTransactionOptions()
    ) {
      (transaction: inout DesignTransaction) throws(DesignDatabaseError)
        -> (DesignEntityID, DesignEntityID) in
      let container = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let shape = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let containerKey = DesignEntityKey(databaseID: root.databaseID, entityID: container)
      let shapeKey = DesignEntityKey(databaseID: root.databaseID, entityID: shape)
      try transaction.setField(entity: containerKey, field: fixture.nameField, value: .string("top"))
      try transaction.setField(entity: shapeKey, field: fixture.nameField, value: .string("shape"))
      try transaction.replaceSpatialEntries(
        entity: shapeKey,
        entries: [
          DesignSpatialEntry(
            container: container,
            bounds: try DesignIntegerBounds(
              minimumX: 10,
              minimumY: 10,
              maximumX: 20,
              maximumY: 20
            )
          )
        ]
      )
      return (container, shape)
    }
    let snapshot = try await database.snapshot(at: result.candidateRevision)
    let query = try DesignQuery(
      source: .spatial(
        container: result.value.0,
        layer: nil,
        bounds: try DesignIntegerBounds(
          minimumX: 15,
          minimumY: 15,
          maximumX: 25,
          maximumY: 25
        ),
        relation: .intersects
      ),
      executionPolicy: try DesignQueryExecutionPolicy()
    )
    let queryResult = try snapshot.execute(query)
    #expect(queryResult.records.map(\.key.entityID) == [result.value.1])
    #expect(queryResult.explain.selectedIndex == .spatial)
    #expect(!queryResult.explain.admittedFullScan)
    try await database.close()
  }

  @Test
  func hierarchyAndConnectivityQueriesUseImmutableIndexes() async throws {
    let fixture = try makeFixture()
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))
    let result = try await database.withTransaction(
      from: root,
      options: try DesignTransactionOptions()
    ) {
      (transaction: inout DesignTransaction) throws(DesignDatabaseError)
        -> (DesignEntityID, DesignEntityID, DesignEntityID) in
      let parent = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let child = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let net = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      for (entity, name) in [(parent, "parent"), (child, "child"), (net, "net")] {
        let key = DesignEntityKey(databaseID: root.databaseID, entityID: entity)
        try transaction.setField(entity: key, field: fixture.nameField, value: .string(name))
      }
      try transaction.replaceRelation(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: child),
        relation: fixture.parentRelation,
        targets: [parent]
      )
      try transaction.replaceRelation(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: child),
        relation: fixture.connectivityRelation,
        targets: [net]
      )
      try transaction.replaceRelation(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: child),
        relation: fixture.crossFacetRelation,
        targets: [net]
      )
      try transaction.replaceRelation(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: child),
        relation: fixture.dependencyRelation,
        targets: [parent]
      )
      return (parent, child, net)
    }
    let snapshot = try await database.snapshot(at: result.candidateRevision)

    let hierarchy = try snapshot.execute(DesignQuery(
      source: .hierarchyChildren(parent: result.value.0),
      executionPolicy: try DesignQueryExecutionPolicy()
    ))
    #expect(hierarchy.records.map(\.key.entityID) == [result.value.1])
    #expect(hierarchy.explain.selectedIndex == .hierarchy)
    #expect(hierarchy.explain.estimatedScanCount == 1)
    #expect(!hierarchy.explain.admittedFullScan)

    let connectivity = try snapshot.execute(DesignQuery(
      source: .connected(
        start: [result.value.2],
        relations: [fixture.connectivityRelation]
      ),
      executionPolicy: try DesignQueryExecutionPolicy()
    ))
    #expect(connectivity.records.map(\.key.entityID) == [result.value.1, result.value.2])
    #expect(connectivity.explain.selectedIndex == .connectivity)
    #expect(connectivity.explain.estimatedScanCount == 2)
    #expect(!connectivity.explain.admittedFullScan)

    let named = try snapshot.execute(DesignQuery(
      source: .name(
        facet: fixture.facet,
        kind: fixture.kind,
        field: fixture.nameField,
        value: "parent"
      ),
      executionPolicy: try DesignQueryExecutionPolicy()
    ))
    #expect(named.records.map(\.key.entityID) == [result.value.0])
    #expect(named.explain.selectedIndex == .name)
    #expect(named.explain.estimatedScanCount == 1)

    let crossFacet = try snapshot.execute(DesignQuery(
      source: .crossFacet(
        start: [result.value.1],
        relations: [fixture.crossFacetRelation]
      ),
      executionPolicy: try DesignQueryExecutionPolicy()
    ))
    #expect(crossFacet.records.map(\.key.entityID) == [result.value.2])
    #expect(crossFacet.explain.selectedIndex == .crossFacet)

    let dependents = try snapshot.execute(DesignQuery(
      source: .dependents(
        of: [result.value.0],
        relations: [fixture.dependencyRelation]
      ),
      executionPolicy: try DesignQueryExecutionPolicy()
    ))
    #expect(dependents.records.map(\.key.entityID) == [result.value.1])
    #expect(dependents.explain.selectedIndex == .dependency)
    try await database.close()
  }

  @Test
  func crossDatabaseReferenceFailsExplicitly() async throws {
    let fixture = try makeFixture()
    let first = try await makeProvider(scopeLow: 1).create(fixture.request)
    let second = try await makeProvider(scopeLow: 2).create(fixture.request)
    let foreign = try await second.resolve(.named(.main))

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await first.snapshot(at: foreign)
    }
    try await first.close()
    try await second.close()
  }

  @Test
  func requestedGrantEscalationFailsBeforeDatabaseCreation() async throws {
    let fixture = try makeFixture()
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x444442,
      low: 10
    )
    let authority = NativeDesignDatabaseAuthorizationAuthority(
      grantsBySubjectScope: [
        subjectScopeID: DesignDatabaseAuthorizationGrantSet([.read])
      ]
    )
    let provider = NativeDesignDatabaseProvider(
      authorizationSubjectScopeID: subjectScopeID,
      requestedAuthorization: DesignDatabaseAuthorizationGrantSet([
        .read,
        .proposeCandidate,
      ]),
      authorizer: authority
    )

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await provider.create(fixture.request)
    }
  }

  @Test
  func authorizationIsRevalidatedForEachProtectedOperation() async throws {
    let fixture = try makeFixture()
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x444442,
      low: 11
    )
    let initialGrants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .proposeCandidate,
    ])
    let authority = NativeDesignDatabaseAuthorizationAuthority(
      grantsBySubjectScope: [subjectScopeID: initialGrants]
    )
    let database = try await NativeDesignDatabaseProvider(
      authorizationSubjectScopeID: subjectScopeID,
      requestedAuthorization: initialGrants,
      authorizer: authority
    ).create(fixture.request)
    let root = try await database.resolve(.named(.main))

    await authority.replaceGrants(
      DesignDatabaseAuthorizationGrantSet([.read]),
      for: subjectScopeID
    )

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await database.withTransaction(
        from: root,
        options: try DesignTransactionOptions()
      ) { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> Void in
        let entity = try transaction.createEntity(
          facet: fixture.facet,
          kind: fixture.kind
        )
        try transaction.setField(
          entity: DesignEntityKey(
            databaseID: root.databaseID,
            entityID: entity
          ),
          field: fixture.nameField,
          value: .string("unauthorized")
        )
      }
    }
    #expect(try await database.resolve(.named(.main)) == root)

    await authority.replaceGrants(
      DesignDatabaseAuthorizationGrantSet([]),
      for: subjectScopeID
    )
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await database.resolve(.named(.main))
    }
    try await database.close()
  }

  @Test
  func unavailableIndexRequiresExplicitFullScanAdmission() async throws {
    let fixture = try makeFixture(indexes: [.name])
    let database = try await makeProvider().create(fixture.request)
    let root = try await database.resolve(.named(.main))
    let result = try await database.withTransaction(
      from: root,
      options: try DesignTransactionOptions()
    ) {
      (transaction: inout DesignTransaction) throws(DesignDatabaseError)
        -> (DesignEntityID, DesignEntityID) in
      let parent = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      let child = try transaction.createEntity(facet: fixture.facet, kind: fixture.kind)
      for (entity, name) in [(parent, "parent"), (child, "child")] {
        try transaction.setField(
          entity: DesignEntityKey(databaseID: root.databaseID, entityID: entity),
          field: fixture.nameField,
          value: .string(name)
        )
      }
      try transaction.replaceRelation(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: child),
        relation: fixture.parentRelation,
        targets: [parent]
      )
      return (parent, child)
    }
    let snapshot = try await database.snapshot(at: result.candidateRevision)

    #expect(throws: DesignDatabaseError.self) {
      _ = try snapshot.execute(DesignQuery(
        source: .hierarchyChildren(parent: result.value.0),
        executionPolicy: try DesignQueryExecutionPolicy()
      ))
    }
    let admitted = try snapshot.execute(DesignQuery(
      source: .hierarchyChildren(parent: result.value.0),
      executionPolicy: try DesignQueryExecutionPolicy(allowsFullScan: true)
    ))
    #expect(admitted.records.map(\.key.entityID) == [result.value.1])
    #expect(admitted.explain.admittedFullScan)
    #expect(admitted.explain.estimatedScanCount == 2)
    try await database.close()
  }

  private func makeProvider(
    scopeLow: UInt64 = 1
  ) throws -> NativeDesignDatabaseProvider {
    let authorization = try makeAuthorization(scopeLow: scopeLow)
    return NativeDesignDatabaseProvider(
      authorizationSubjectScopeID: authorization.subjectScopeID,
      requestedAuthorization: authorization.grants,
      authorizer: authorization.authority
    )
  }

  private func makeAuthorization(
    scopeLow: UInt64 = 1
  ) throws -> AuthorizationFixture {
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x444442,
      low: scopeLow
    )
    let grants = DesignDatabaseAuthorizationGrantSet(
      DesignDatabaseAuthorizationGrant.allCases
    )
    return AuthorizationFixture(
      subjectScopeID: subjectScopeID,
      grants: grants,
      authority: NativeDesignDatabaseAuthorizationAuthority(
        grantsBySubjectScope: [subjectScopeID: grants]
      )
    )
  }

  private func makeFixture(
    indexes: Set<DesignIndexKind> = [
      .name, .hierarchy, .connectivity, .spatial, .crossFacet, .dependency,
    ]
  ) throws -> Fixture {
    let facet = try DesignFacetID(rawValue: "logic")
    let kind = try DesignEntityKindID(rawValue: "module")
    let nameField = try DesignFieldID(rawValue: "name")
    let parentRelation = try DesignRelationKindID(rawValue: "parent")
    let connectivityRelation = try DesignRelationKindID(rawValue: "connected-to")
    let crossFacetRelation = try DesignRelationKindID(rawValue: "cross-facet")
    let dependencyRelation = try DesignRelationKindID(rawValue: "depends-on")
    let digest = try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: "a", count: 64)
    )
    let descriptor = try DesignSchemaDescriptor(
      schemaID: try DesignSchemaID(rawValue: "lsi.logic"),
      facetID: facet,
      version: SchemaVersion(major: 1, minor: 0, patch: 0),
      canonicalDigest: digest
    )
    let entity = try DesignEntitySchema(
      kindID: kind,
      fields: [
        DesignFieldSchema(
          id: nameField,
          valueKind: .string,
          isRequired: true,
          isNameIndexSource: true
        )
      ],
      relations: [
        DesignRelationSchema(id: parentRelation, isHierarchyParent: true),
        DesignRelationSchema(id: connectivityRelation, isConnectivity: true),
        DesignRelationSchema(id: crossFacetRelation, isCrossFacet: true),
        DesignRelationSchema(id: dependencyRelation, isDependency: true),
      ],
      uniqueConstraints: [
        try DesignUniqueConstraint(
          id: DesignUniqueConstraintID(rawValue: "unique-name"),
          fields: [nameField]
        )
      ]
    )
    let schema = try DesignFacetSchema(
      descriptor: descriptor,
      entities: [entity],
      indexes: indexes
    )
    return Fixture(
      facet: facet,
      kind: kind,
      nameField: nameField,
      parentRelation: parentRelation,
      connectivityRelation: connectivityRelation,
      crossFacetRelation: crossFacetRelation,
      dependencyRelation: dependencyRelation,
      request: DesignReferenceDatabaseCreateRequest(
        schemas: [schema],
        capabilities: try DesignCapabilitySet([])
      )
    )
  }

  private struct Fixture: Sendable {
    let facet: DesignFacetID
    let kind: DesignEntityKindID
    let nameField: DesignFieldID
    let parentRelation: DesignRelationKindID
    let connectivityRelation: DesignRelationKindID
    let crossFacetRelation: DesignRelationKindID
    let dependencyRelation: DesignRelationKindID
    let request: DesignReferenceDatabaseCreateRequest
  }

  private struct AuthorizationFixture {
    let subjectScopeID: DesignAuthorizationSubjectScopeID
    let grants: DesignDatabaseAuthorizationGrantSet
    let authority: NativeDesignDatabaseAuthorizationAuthority
  }
}
