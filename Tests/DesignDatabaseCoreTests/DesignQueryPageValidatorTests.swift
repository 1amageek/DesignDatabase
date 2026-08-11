import CircuiteFoundation
import DesignDatabaseCore
import Testing

@Suite("Design query page validator")
struct DesignQueryPageValidatorTests {
  @Test("exact first page remains bound to its request")
  func acceptsExactFirstPage() throws {
    let fixture = try QueryPageValidationFixture()

    try DesignQueryPageValidator().validate(
      fixture.page,
      for: fixture.request,
      expectedRevision: fixture.revision,
      expectedDesignSchemaBundleDigest: fixture.schemaDigest
    )
  }

  @Test("row outside the requested prefix is rejected")
  func rejectsRowOutsidePrefix() throws {
    let fixture = try QueryPageValidationFixture(
      rowKey: [0x62],
      keyPrefix: [0x61]
    )

    #expect(throws: DesignDatabaseError.self) {
      try DesignQueryPageValidator().validate(
        fixture.page,
        for: fixture.request,
        expectedRevision: fixture.revision,
        expectedDesignSchemaBundleDigest: fixture.schemaDigest
      )
    }
  }

  @Test("resource report cannot exceed the original budget")
  func rejectsReportBeyondBudget() throws {
    let fixture = try QueryPageValidationFixture(
      reportedWorkCount: 33,
      maximumWorkCount: 32
    )

    #expect(throws: DesignDatabaseError.self) {
      try DesignQueryPageValidator().validate(
        fixture.page,
        for: fixture.request,
        expectedRevision: fixture.revision,
        expectedDesignSchemaBundleDigest: fixture.schemaDigest
      )
    }
  }
}

private struct QueryPageValidationFixture {
  let revision: DesignRevisionReference
  let schemaDigest: ContentDigest
  let request: DesignQueryRequest
  let page: DesignQueryPage

  init(
    rowKey: [UInt8] = [0x61],
    keyPrefix: [UInt8]? = [0x61],
    reportedWorkCount: UInt64 = 1,
    maximumWorkCount: UInt64 = 32
  ) throws {
    let databaseID = try DesignDatabaseID(high: 901, low: 1)
    revision = DesignRevisionReference(
      databaseID: databaseID,
      revisionID: DesignRevisionID(high: 901, low: 2)
    )
    schemaDigest = try Self.digest("1")
    let semanticDigest = try Self.digest("2")
    let budget = try DesignQueryBudget(
      maximumResultCount: 8,
      maximumNodeFetchCount: 8,
      maximumEncodedReadByteCount: 1_024,
      maximumDecodedByteCount: 1_024,
      maximumOutputByteCount: 1_024,
      maximumWorkCount: maximumWorkCount
    )
    request = try DesignQueryRequest(
      family: .entity,
      keyPrefix: keyPrefix.map { try DesignCanonicalKey(bytes: $0) },
      maximumPageResultCount: 8,
      budget: budget
    )
    let row = try DesignProjectionEntry(
      key: DesignCanonicalKey(bytes: rowKey),
      value: [0x01]
    )
    let materialization = try DesignProjectionMaterializationReference(
      semanticDescriptorDigest: semanticDigest,
      bindingGeneration: 1,
      physicalCodecVersion: DesignProjectionPhysicalCodecVersion(
        major: 1,
        minor: 0
      ),
      physicalProfileDigest: try Self.digest("3"),
      rootNodeDigest: try Self.digest("4")
    )
    page = try DesignQueryPage(
      revision: revision,
      designSchemaBundleDigest: schemaDigest,
      projectionSemanticDigest: semanticDigest,
      materialization: materialization,
      rows: [row],
      continuation: nil,
      completion: .sourceExhausted,
      report: DesignQueryResourceReport(
        resultCount: 1,
        nodeFetchCount: 1,
        encodedReadByteCount: 1,
        decodedByteCount: 1,
        outputByteCount: 1,
        workCount: reportedWorkCount
      )
    )
  }

  private static func digest(_ character: Character) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: character, count: 64)
    )
  }
}
