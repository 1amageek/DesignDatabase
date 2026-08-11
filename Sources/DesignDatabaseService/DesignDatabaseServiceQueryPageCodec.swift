import CircuiteFoundation
import DesignDatabaseCore
import Foundation

public enum DesignDatabaseServiceQueryPageCodec {
  public static let currentVersion: UInt16 = 1

  private static let magic: [UInt8] = [0x44, 0x44, 0x42, 0x51]
  private static let headerByteCount: UInt64 = 24

  public static func encode(
    _ page: DesignQueryPage,
    budget: DesignDatabaseServiceQueryPageCodecBudget
  ) throws(DesignDatabaseServiceQueryPageCodecError) -> [UInt8] {
    let metadata = Metadata(page: page)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let metadataBytes: [UInt8]
    do {
      metadataBytes = Array(try encoder.encode(metadata))
    } catch {
      throw .invalidMetadata(reason: String(describing: error))
    }
    let metadataCount = try exactUInt64(metadataBytes.count)
    try requireWithinBudget(
      kind: "metadata bytes",
      requested: metadataCount,
      limit: budget.maximumMetadataByteCount
    )
    let rowCount = try exactUInt64(page.rows.count)
    try requireWithinBudget(
      kind: "row count",
      requested: rowCount,
      limit: budget.maximumRowCount
    )

    var frameByteCount = headerByteCount
    frameByteCount = try adding(frameByteCount, metadataCount)
    for row in page.rows {
      let keyCount = try exactUInt64(row.key.bytes.count)
      let valueCount = try exactUInt64(row.value.count)
      frameByteCount = try adding(frameByteCount, 12)
      frameByteCount = try adding(frameByteCount, keyCount)
      frameByteCount = try adding(frameByteCount, valueCount)
    }
    try requireWithinBudget(
      kind: "frame bytes",
      requested: frameByteCount,
      limit: budget.maximumFrameByteCount
    )
    guard let capacity = Int(exactly: frameByteCount) else {
      throw .integerOverflow
    }

    var bytes: [UInt8] = []
    bytes.reserveCapacity(capacity)
    bytes.append(contentsOf: magic)
    append(currentVersion, to: &bytes)
    append(UInt16(0), to: &bytes)
    append(metadataCount, to: &bytes)
    append(rowCount, to: &bytes)
    bytes.append(contentsOf: metadataBytes)
    for row in page.rows {
      guard let keyCount = UInt32(exactly: row.key.bytes.count) else {
        throw .integerOverflow
      }
      append(keyCount, to: &bytes)
      append(try exactUInt64(row.value.count), to: &bytes)
      bytes.append(contentsOf: row.key.bytes)
      bytes.append(contentsOf: row.value)
    }
    guard bytes.count == capacity else { throw .integerOverflow }
    return bytes
  }

  public static func decode(
    _ bytes: [UInt8],
    budget: DesignDatabaseServiceQueryPageCodecBudget
  ) throws(DesignDatabaseServiceQueryPageCodecError) -> DesignQueryPage {
    let frameByteCount = try exactUInt64(bytes.count)
    try requireWithinBudget(
      kind: "frame bytes",
      requested: frameByteCount,
      limit: budget.maximumFrameByteCount
    )
    var cursor = Cursor(bytes: bytes)
    guard try cursor.read(count: magic.count) == magic else {
      throw .invalidMagic
    }
    let version = try cursor.readUInt16()
    guard version == currentVersion else {
      throw .unsupportedVersion(version)
    }
    let flags = try cursor.readUInt16()
    guard flags == 0 else { throw .unsupportedFlags(flags) }
    let metadataCount = try cursor.readUInt64()
    let rowCount = try cursor.readUInt64()
    try requireWithinBudget(
      kind: "metadata bytes",
      requested: metadataCount,
      limit: budget.maximumMetadataByteCount
    )
    try requireWithinBudget(
      kind: "row count",
      requested: rowCount,
      limit: budget.maximumRowCount
    )
    guard let metadataLength = Int(exactly: metadataCount),
          let decodedRowCount = Int(exactly: rowCount) else {
      throw .integerOverflow
    }
    let metadataBytes = try cursor.read(count: metadataLength)
    let metadata: Metadata
    do {
      metadata = try JSONDecoder().decode(
        Metadata.self,
        from: Data(metadataBytes)
      )
    } catch {
      throw .invalidMetadata(reason: String(describing: error))
    }

    var rows: [DesignProjectionEntry] = []
    rows.reserveCapacity(decodedRowCount)
    for _ in 0..<decodedRowCount {
      let keyCount = try cursor.readUInt32()
      let valueCount = try cursor.readUInt64()
      guard keyCount <= UInt32(DesignCanonicalKey.maximumByteCount) else {
        throw .budgetExceeded(
          kind: "row key bytes",
          limit: UInt64(DesignCanonicalKey.maximumByteCount),
          requested: UInt64(keyCount)
        )
      }
      guard valueCount <= UInt64(DesignProjectionEntry.maximumValueByteCount)
      else {
        throw .budgetExceeded(
          kind: "row value bytes",
          limit: UInt64(DesignProjectionEntry.maximumValueByteCount),
          requested: valueCount
        )
      }
      guard let keyLength = Int(exactly: keyCount),
            let valueLength = Int(exactly: valueCount) else {
        throw .integerOverflow
      }
      let keyBytes = try cursor.read(count: keyLength)
      let valueBytes = try cursor.read(count: valueLength)
      do {
        rows.append(try DesignProjectionEntry(
          key: DesignCanonicalKey(bytes: keyBytes),
          value: valueBytes
        ))
      } catch {
        throw .invalidPage(reason: String(describing: error))
      }
    }
    guard cursor.remainingByteCount == 0 else {
      throw .trailingBytes(try exactUInt64(cursor.remainingByteCount))
    }
    guard rowCount <= metadata.report.resultCount else {
      throw .invalidPage(
        reason: "A binary query page contains more rows than its cumulative result count."
      )
    }
    do {
      return try DesignQueryPage(
        revision: metadata.revision,
        designSchemaBundleDigest: metadata.designSchemaBundleDigest,
        projectionSemanticDigest: metadata.projectionSemanticDigest,
        materialization: metadata.materialization,
        rows: rows,
        continuation: metadata.continuation,
        completion: metadata.completion,
        report: metadata.report
      )
    } catch {
      throw .invalidPage(reason: String(describing: error))
    }
  }

  private static func requireWithinBudget(
    kind: String,
    requested: UInt64,
    limit: UInt64
  ) throws(DesignDatabaseServiceQueryPageCodecError) {
    guard requested <= limit else {
      throw .budgetExceeded(kind: kind, limit: limit, requested: requested)
    }
  }

  private static func exactUInt64(
    _ value: Int
  ) throws(DesignDatabaseServiceQueryPageCodecError) -> UInt64 {
    guard let result = UInt64(exactly: value) else { throw .integerOverflow }
    return result
  }

  private static func adding(
    _ lhs: UInt64,
    _ rhs: UInt64
  ) throws(DesignDatabaseServiceQueryPageCodecError) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw .integerOverflow }
    return result
  }

  private static func append(_ value: UInt16, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  private static func append(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  private static func append(_ value: UInt64, to bytes: inout [UInt8]) {
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
    }
  }
}

private extension DesignDatabaseServiceQueryPageCodec {
  struct Metadata: Codable {
    let revision: DesignRevisionReference
    let designSchemaBundleDigest: ContentDigest
    let projectionSemanticDigest: ContentDigest
    let materialization: DesignProjectionMaterializationReference
    let continuation: DesignQueryContinuation?
    let completion: DesignQueryCompletion
    let report: DesignQueryResourceReport

    init(page: DesignQueryPage) {
      revision = page.revision
      designSchemaBundleDigest = page.designSchemaBundleDigest
      projectionSemanticDigest = page.projectionSemanticDigest
      materialization = page.materialization
      continuation = page.continuation
      completion = page.completion
      report = page.report
    }
  }

  struct Cursor {
    let bytes: [UInt8]
    private(set) var offset = 0

    var remainingByteCount: Int { bytes.count - offset }

    mutating func read(
      count: Int
    ) throws(DesignDatabaseServiceQueryPageCodecError) -> [UInt8] {
      guard count >= 0, count <= remainingByteCount else { throw .truncated }
      let end = offset + count
      let result = Array(bytes[offset..<end])
      offset = end
      return result
    }

    mutating func readUInt16()
      throws(DesignDatabaseServiceQueryPageCodecError) -> UInt16 {
      let value = try read(count: 2)
      return (UInt16(value[0]) << 8) | UInt16(value[1])
    }

    mutating func readUInt32()
      throws(DesignDatabaseServiceQueryPageCodecError) -> UInt32 {
      let value = try read(count: 4)
      return (UInt32(value[0]) << 24)
        | (UInt32(value[1]) << 16)
        | (UInt32(value[2]) << 8)
        | UInt32(value[3])
    }

    mutating func readUInt64()
      throws(DesignDatabaseServiceQueryPageCodecError) -> UInt64 {
      let value = try read(count: 8)
      var result: UInt64 = 0
      for byte in value { result = (result << 8) | UInt64(byte) }
      return result
    }
  }
}
