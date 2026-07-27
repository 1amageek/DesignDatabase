import CircuiteFoundation
import DesignDatabaseCore
import DesignDatabaseNative
import DesignDatabaseService
import Testing

@Suite
struct DesignDatabaseServiceTests {
  @Test
  func negotiationFailsClosedAndSessionShutdownRejectsOperations() async throws {
    let fixture = try makeFixture()
    let database = try await NativeDesignDatabaseProvider().create(fixture.request)
    let service = InProcessDesignDatabaseService(
      database: database,
      schemas: [fixture.schema.descriptor],
      capabilities: try DesignCapabilitySet([])
    )
    let compatible = try await service.negotiate(DesignServiceNegotiationRequest(
      requiredSchemas: [
        DesignSchemaRequirement(
          schemaID: fixture.schema.descriptor.schemaID,
          versions: try SchemaVersionRange(
            lowerBound: SchemaVersion(major: 1, minor: 0, patch: 0),
            upperBound: SchemaVersion(major: 2, minor: 0, patch: 0)
          )
        )
      ],
      requiredCapabilities: []
    ))
    #expect(compatible.report.isCompatible)

    await #expect(throws: DesignDatabaseError.self) {
      _ = try await service.negotiate(DesignServiceNegotiationRequest(
        requiredSchemas: [
          DesignSchemaRequirement(
            schemaID: try DesignSchemaID(rawValue: "missing.schema"),
            versions: try SchemaVersionRange(
              lowerBound: SchemaVersion(major: 1, minor: 0, patch: 0),
              upperBound: SchemaVersion(major: 2, minor: 0, patch: 0)
            )
          )
        ],
        requiredCapabilities: []
      ))
    }

    let session = try await service.openSession(leaseDuration: .seconds(60))
    let root = try await session.resolve(.named(.main))
    #expect(root.databaseID == database.databaseID)
    await session.shutdown()
    await #expect(throws: DesignDatabaseError.self) {
      _ = try await session.resolve(.named(.main))
    }
    try await service.shutdown()
  }

  private func makeFixture() throws -> Fixture {
    let facet = try DesignFacetID(rawValue: "service")
    let descriptor = try DesignSchemaDescriptor(
      schemaID: try DesignSchemaID(rawValue: "lsi.service"),
      facetID: facet,
      version: SchemaVersion(major: 1, minor: 0, patch: 0),
      canonicalDigest: try ContentDigest(
        algorithm: .sha256,
        hexadecimalValue: String(repeating: "b", count: 64)
      )
    )
    let schema = try DesignFacetSchema(
      descriptor: descriptor,
      entities: [],
      indexes: []
    )
    return Fixture(
      schema: schema,
      request: DesignDatabaseCreateRequest(
        schemas: [schema],
        capabilities: try DesignCapabilitySet([])
      )
    )
  }

  private struct Fixture: Sendable {
    let schema: DesignFacetSchema
    let request: DesignDatabaseCreateRequest
  }
}
