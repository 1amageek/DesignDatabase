import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFoundation
import DesignDatabaseCore
import DesignDatabaseNative
import DesignDatabasePersistence
import Foundation
import Testing

@Suite
struct FileDesignDatabasePersistenceTests {
  @Test
  func secondInProcessOwnerIsRejected() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("design-database-lock-\(UUID().uuidString)", isDirectory: true)
    defer { removeTestDirectory(rootURL) }
    let first = try FileDesignDatabasePersistence(rootURL: rootURL)

    #expect(throws: DesignDatabaseError.self) {
      _ = try FileDesignDatabasePersistence(rootURL: rootURL)
    }
    try await first.close()
  }

  @Test
  func truncatedWALFailsWithoutReturningAnImage() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("design-database-wal-\(UUID().uuidString)", isDirectory: true)
    defer { removeTestDirectory(rootURL) }
    let persistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    try Data("truncated".utf8).write(
      to: rootURL.appendingPathComponent("pending.wal", isDirectory: false)
    )

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await persistence.load()
    }
    try await persistence.close()
  }

  @Test
  func databaseReopensAtPromotedRevision() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("design-database-\(UUID().uuidString)", isDirectory: true)
    defer { removeTestDirectory(rootURL) }

    let schema = try makeSchema()
    let firstPersistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    let firstProvider = try makeProvider(persistence: firstPersistence)
    let first = try await firstProvider.create(
      DesignReferenceDatabaseCreateRequest(
        schemas: [schema.value],
        capabilities: try DesignCapabilitySet([])
      )
    )
    let root = try await first.resolve(.named(.main))
    let transaction = try await first.withTransaction(
      from: root,
      options: try DesignTransactionOptions()
    ) { (transaction: inout DesignTransaction) throws(DesignDatabaseError) -> DesignEntityID in
      let identifier = try transaction.createEntity(facet: schema.facet, kind: schema.kind)
      try transaction.setField(
        entity: DesignEntityKey(databaseID: root.databaseID, entityID: identifier),
        field: schema.field,
        value: .string("persisted")
      )
      return identifier
    }
    _ = try await first.compareAndSetReference(
      .main,
      expected: root,
      desired: transaction.candidateRevision
    )
    try await first.close()

    let secondPersistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    let second = try await makeProvider(persistence: secondPersistence).open()
    let reopened = try await second.resolve(.named(.main))
    #expect(reopened == transaction.candidateRevision)
    let snapshot = try await second.snapshot(at: reopened)
    let record = try snapshot.entity(
      DesignEntityKey(databaseID: reopened.databaseID, entityID: transaction.value)
    )
    #expect(record.fields[schema.field] == .string("persisted"))
    try await second.close()
  }

  @Test
  func retentionOutcomesPersistWithoutCrossSubjectCollisionOrDisclosure() async throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "design-database-retention-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { removeTestDirectory(rootURL) }

    let firstPersistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    let first = try await makeProvider(
      persistence: firstPersistence,
      scopeLow: 1
    ).create(
      DesignReferenceDatabaseCreateRequest(
        schemas: [],
        capabilities: DesignCapabilitySet([])
      )
    )
    let root = try await first.resolve(.named(.main))
    let firstRequest = try makeRetentionRequest(
      operation: "shared-local-operation",
      claim: "first-subject-claim",
      revision: root
    )
    let firstReceipt = try appliedReceipt(try await first.retain(firstRequest))
    let firstOperation = DesignDatabaseOperationReference(
      databaseID: first.databaseID,
      authorizationSubjectScopeID: first.authorizationSubjectScopeID,
      operationID: firstRequest.operationID
    )
    try await first.close()

    let secondPersistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    let secondGrants = DesignDatabaseAuthorizationGrantSet([
      .read,
      .retain,
      .inspectOwnOperationOutcome,
    ])
    let second = try await makeProvider(
      persistence: secondPersistence,
      scopeLow: 2,
      grants: secondGrants
    ).open()
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await second.retentionStatus(
        operation: firstOperation,
        requestDigest: firstRequest.requestDigest
      )
    }

    let secondRequest = try makeRetentionRequest(
      operation: "shared-local-operation",
      claim: "second-subject-claim",
      revision: root
    )
    let secondReceipt = try appliedReceipt(try await second.retain(secondRequest))
    #expect(secondReceipt.operation.operationID == firstReceipt.operation.operationID)
    #expect(
      secondReceipt.operation.authorizationSubjectScopeID
        != firstReceipt.operation.authorizationSubjectScopeID
    )
    try await second.close()

    let administratorPersistence = try FileDesignDatabasePersistence(rootURL: rootURL)
    let administrator = try await makeProvider(
      persistence: administratorPersistence,
      scopeLow: 2,
      grants: DesignDatabaseAuthorizationGrantSet([.read, .administer])
    ).open()
    #expect(
      try await administrator.retentionStatus(
        operation: firstOperation,
        requestDigest: firstRequest.requestDigest
      ) == .applied(firstReceipt)
    )
    try await administrator.close()
  }

  private func makeSchema() throws -> SchemaFixture {
    let facet = try DesignFacetID(rawValue: "logic")
    let kind = try DesignEntityKindID(rawValue: "module")
    let field = try DesignFieldID(rawValue: "name")
    let descriptor = try DesignSchemaDescriptor(
      schemaID: try DesignSchemaID(rawValue: "lsi.logic"),
      facetID: facet,
      version: SchemaVersion(major: 1, minor: 0, patch: 0),
      canonicalDigest: try ContentDigest(
        algorithm: .sha256,
        hexadecimalValue: String(repeating: "b", count: 64)
      )
    )
    return SchemaFixture(
      facet: facet,
      kind: kind,
      field: field,
      value: try DesignFacetSchema(
        descriptor: descriptor,
        entities: [
          try DesignEntitySchema(
            kindID: kind,
            fields: [DesignFieldSchema(id: field, valueKind: .string, isRequired: true)],
            relations: []
          )
        ],
        indexes: []
      )
    )
  }

  private func makeProvider(
    persistence: any DesignDatabasePersisting,
    scopeLow: UInt64 = 1,
    grants: DesignDatabaseAuthorizationGrantSet = DesignDatabaseAuthorizationGrantSet(
      DesignDatabaseAuthorizationGrant.allCases
    )
  ) throws -> NativeDesignDatabaseProvider {
    let subjectScopeID = try DesignAuthorizationSubjectScopeID(
      high: 0x444442,
      low: scopeLow
    )
    return NativeDesignDatabaseProvider(
      authorizationSubjectScopeID: subjectScopeID,
      grantedAuthorization: grants,
      persistence: persistence
    )
  }

  private func makeRetentionRequest(
    operation: String,
    claim: String,
    revision: DesignRevisionReference
  ) throws -> DesignRevisionRetentionRequest {
    let operationID = try DesignDatabaseOperationID(rawValue: operation)
    let claimID = try DesignRevisionRetentionID(rawValue: claim)
    let reason = try DesignRevisionRetentionReason(rawValue: "release-bundle")
    let evidenceDigest = try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: "c", count: 64)
    )
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

  private func appliedReceipt(
    _ submission: DesignRevisionRetentionSubmission
  ) throws -> DesignRevisionRetentionReceipt {
    guard case .applied(let receipt) = submission else {
      throw DesignDatabaseError.corruption("Expected an applied retention receipt.")
    }
    return receipt
  }

  private func removeTestDirectory(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      // Test cleanup must not replace the behavior under test.
    }
  }

  private struct SchemaFixture {
    let facet: DesignFacetID
    let kind: DesignEntityKindID
    let field: DesignFieldID
    let value: DesignFacetSchema
  }
}
