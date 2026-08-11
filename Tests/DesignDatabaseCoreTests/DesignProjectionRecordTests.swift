import CircuiteFoundation
import DesignDatabaseCore
import Foundation
import Testing

@Suite
struct DesignProjectionRecordTests {
  @Test
  func entityProjectionRoundTripsAndSortsByNumericIdentity() throws {
    let first = DesignEntityProjectionRecord(
      entityID: try DesignEntityID(rawValue: 1),
      facetID: try DesignFacetID(rawValue: "logic"),
      kindID: try DesignEntityKindID(rawValue: "module"),
      contentDigest: try digest(repeating: "1")
    )
    let second = DesignEntityProjectionRecord(
      entityID: try DesignEntityID(rawValue: 256),
      facetID: try DesignFacetID(rawValue: "logic"),
      kindID: try DesignEntityKindID(rawValue: "module"),
      contentDigest: try digest(repeating: "2")
    )

    let firstEntry = try first.projectionEntry()
    let secondEntry = try second.projectionEntry()

    #expect(firstEntry.key < secondEntry.key)
    #expect(try DesignEntityProjectionRecord(projectionEntry: firstEntry) == first)
    #expect(try DesignEntityProjectionRecord(projectionEntry: secondEntry) == second)
  }

  @Test
  func projectionChangeRejectsEmptyAndMovedKeys() throws {
    let first = try entry(key: [1], value: [10])
    let second = try entry(key: [2], value: [20])

    #expect(throws: DesignDatabaseError.self) {
      _ = try DesignProjectionChange(
        family: .entity,
        before: nil,
        after: nil
      )
    }
    #expect(throws: DesignDatabaseError.self) {
      _ = try DesignProjectionChange(
        family: .entity,
        before: first,
        after: second
      )
    }
    #expect(throws: DesignDatabaseError.self) {
      _ = try DesignProjectionChange(
        family: .entity,
        before: first,
        after: first
      )
    }
  }

  @Test
  func relationOccurrencesPreserveDirectionOrderAndMultiplicity() throws {
    let owner = try DesignEntityID(rawValue: 7)
    let relation = try DesignRelationKindID(rawValue: "contains")
    let first = try DesignRelationOccurrenceRecord(
      projectionFamily: .hierarchy,
      occurrenceID: DesignRelationOccurrenceID(rawValue: 11),
      ownerEntityID: owner,
      relationKindID: relation,
      target: .local(owner),
      orderKey: DesignCanonicalKey(bytes: [1]),
      attributesDigest: nil
    )
    let repeated = try DesignRelationOccurrenceRecord(
      projectionFamily: .hierarchy,
      occurrenceID: DesignRelationOccurrenceID(rawValue: 12),
      ownerEntityID: owner,
      relationKindID: relation,
      target: .local(owner),
      orderKey: DesignCanonicalKey(bytes: [1]),
      attributesDigest: nil
    )
    let reordered = try DesignRelationOccurrenceRecord(
      projectionFamily: .hierarchy,
      occurrenceID: DesignRelationOccurrenceID(rawValue: 13),
      ownerEntityID: owner,
      relationKindID: relation,
      target: .local(owner),
      orderKey: DesignCanonicalKey(bytes: [2]),
      attributesDigest: nil
    )

    let firstEntries = try first.projectionEntries()
    let repeatedEntries = try repeated.projectionEntries()
    let reorderedEntries = try reordered.projectionEntries()

    #expect(firstEntries.count == 2)
    #expect(firstEntries[0].key != firstEntries[1].key)
    #expect(firstEntries[0].key != repeatedEntries[0].key)
    #expect(firstEntries[1].key != repeatedEntries[1].key)
    #expect(firstEntries[0].key < reorderedEntries[0].key)
  }

  @Test
  func exactRelationTargetEncodingIsStableAndDecodeValidatesFamily() throws {
    let exactTarget = DesignRelationOccurrenceTarget.exact(
      DesignEntityReference(
        revision: DesignRevisionReference(
          databaseID: try DesignDatabaseID(high: 1, low: 2),
          revisionID: DesignRevisionID(high: 3, low: 4)
        ),
        facetID: try DesignFacetID(rawValue: "circuit"),
        kindID: try DesignEntityKindID(rawValue: "device"),
        entityID: try DesignEntityID(rawValue: 5)
      )
    )
    let record = try DesignRelationOccurrenceRecord(
      projectionFamily: .dependency,
      occurrenceID: DesignRelationOccurrenceID(rawValue: 6),
      ownerEntityID: DesignEntityID(rawValue: 7),
      relationKindID: DesignRelationKindID(rawValue: "uses"),
      target: exactTarget,
      orderKey: DesignCanonicalKey(bytes: [8]),
      attributesDigest: digest(repeating: "9")
    )

    #expect(try record.projectionEntries() == record.projectionEntries())
    for entry in try record.projectionEntries() {
      #expect(try DesignRelationOccurrenceRecord(projectionEntry: entry) == record)
    }
    let encoded = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(
      DesignRelationOccurrenceRecord.self,
      from: encoded
    ) == record)

    let invalid = UncheckedRelationOccurrence(
      projectionFamily: .entity,
      occurrenceID: try DesignRelationOccurrenceID(rawValue: 6),
      ownerEntityID: try DesignEntityID(rawValue: 7),
      relationKindID: try DesignRelationKindID(rawValue: "uses"),
      target: exactTarget,
      orderKey: try DesignCanonicalKey(bytes: [8]),
      attributesDigest: nil
    )
    let invalidData = try JSONEncoder().encode(invalid)
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignRelationOccurrenceRecord.self,
        from: invalidData
      )
    }
  }

  private func entry(
    key: [UInt8],
    value: [UInt8]
  ) throws -> DesignProjectionEntry {
    try DesignProjectionEntry(
      key: DesignCanonicalKey(bytes: key),
      value: value
    )
  }

  private func digest(repeating character: Character) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: character, count: 64)
    )
  }

  private struct UncheckedRelationOccurrence: Encodable {
    let projectionFamily: DesignProjectionFamily
    let occurrenceID: DesignRelationOccurrenceID
    let ownerEntityID: DesignEntityID
    let relationKindID: DesignRelationKindID
    let target: DesignRelationOccurrenceTarget
    let orderKey: DesignCanonicalKey
    let attributesDigest: ContentDigest?
  }
}
