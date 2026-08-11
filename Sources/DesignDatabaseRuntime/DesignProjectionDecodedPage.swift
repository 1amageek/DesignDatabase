import CircuiteFoundation
import DesignDatabaseCore

package final class DesignProjectionDecodedPage: Sendable {
  package let digest: ContentDigest
  package let family: DesignProjectionFamily
  package let codecVersion: DesignProjectionPhysicalCodecVersion
  package let physicalProfileDigest: ContentDigest
  package let kind: DesignProjectionNodeKind
  package let level: UInt16
  package let minimumKey: DesignCanonicalKey?
  package let maximumKey: DesignCanonicalKey?
  package let subtreeEntryCount: UInt64
  package let subtreeNodeCount: UInt64
  package let encodedByteCount: UInt64
  package let accountedResidentByteCount: UInt64

  private let entries: [DesignProjectionEntry]
  private let children: [DesignProjectionChildReference]

  package init(
    node: DesignProjectionPhysicalNode
  ) throws(DesignDatabaseRuntimeError) {
    guard let encodedByteCount = UInt64(exactly: node.payload.count) else {
      throw .persistedStateCorrupt(
        reason: "A decoded projection page payload exceeds UInt64."
      )
    }
    digest = node.digest
    family = node.family
    codecVersion = node.codecVersion
    physicalProfileDigest = node.physicalProfileDigest
    kind = node.kind
    level = node.level
    minimumKey = node.minimumKey
    maximumKey = node.maximumKey
    subtreeEntryCount = node.subtreeEntryCount
    subtreeNodeCount = node.subtreeNodeCount
    self.encodedByteCount = encodedByteCount
    entries = node.entries
    children = node.children
    accountedResidentByteCount = try Self.accountedResidentByteCount(
      entries: node.entries,
      children: node.children
    )
  }

  package var entryCount: Int { entries.count }
  package var childCount: Int { children.count }

  package func entry(at index: Int) -> DesignProjectionEntry {
    entries[index]
  }

  package func child(at index: Int) -> DesignProjectionChildReference {
    children[index]
  }

  private static func accountedResidentByteCount(
    entries: [DesignProjectionEntry],
    children: [DesignProjectionChildReference]
  ) throws(DesignDatabaseRuntimeError) -> UInt64 {
    var total: UInt64 = 1
    for entry in entries {
      total = try adding(total, entry.key.bytes.count)
      total = try adding(total, entry.value.count)
    }
    for child in children {
      total = try adding(total, child.nodeDigest.algorithm.rawValue.utf8.count)
      total = try adding(total, child.nodeDigest.hexadecimalValue.utf8.count)
      total = try adding(total, child.minimumKey.bytes.count)
      total = try adding(total, child.maximumKey.bytes.count)
      total = try adding(total, MemoryLayout<UInt64>.size * 2)
      total = try adding(total, MemoryLayout<UInt16>.size)
    }
    return total
  }

  private static func adding(
    _ value: UInt64,
    _ count: Int
  ) throws(DesignDatabaseRuntimeError) -> UInt64 {
    guard let converted = UInt64(exactly: count) else {
      throw .persistedStateCorrupt(
        reason: "A decoded projection page resident byte count exceeds UInt64."
      )
    }
    let (result, overflow) = value.addingReportingOverflow(converted)
    guard !overflow else {
      throw .persistedStateCorrupt(
        reason: "A decoded projection page resident byte count overflowed."
      )
    }
    return result
  }
}
