import CircuiteFoundation
import DesignDatabaseCore

package enum DesignProjectionNodeCodec {
  package static func encodeLeaf(
    _ entries: [DesignProjectionEntry]
  ) throws(DesignDatabaseRuntimeError) -> [UInt8] {
    var bytes: [UInt8] = []
    try appendCount(entries.count, to: &bytes)
    for entry in entries {
      try appendBytes(entry.key.bytes, to: &bytes)
      try appendBytes(entry.value, to: &bytes)
    }
    return bytes
  }

  package static func decodeLeaf(
    _ payload: [UInt8]
  ) throws(DesignDatabaseRuntimeError) -> [DesignProjectionEntry] {
    var reader = DesignProjectionByteReader(payload)
    let count = try reader.readCount()
    var entries: [DesignProjectionEntry] = []
    entries.reserveCapacity(count)
    for _ in 0..<count {
      do {
        entries.append(
          try DesignProjectionEntry(
            key: DesignCanonicalKey(bytes: reader.readBytes()),
            value: reader.readBytes()
          )
        )
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .persistedStateCorrupt(
          reason: "A projection leaf contains an invalid semantic entry."
        )
      }
    }
    try reader.requireExhausted()
    return entries
  }

  package static func encodeInternal(
    _ children: [DesignProjectionChildReference]
  ) throws(DesignDatabaseRuntimeError) -> [UInt8] {
    var bytes: [UInt8] = []
    try appendCount(children.count, to: &bytes)
    for child in children {
      try appendString(child.nodeDigest.algorithm.rawValue, to: &bytes)
      try appendString(child.nodeDigest.hexadecimalValue, to: &bytes)
      try appendBytes(child.minimumKey.bytes, to: &bytes)
      try appendBytes(child.maximumKey.bytes, to: &bytes)
      append(child.subtreeEntryCount, to: &bytes)
      append(child.subtreeNodeCount, to: &bytes)
      append(child.level, to: &bytes)
    }
    return bytes
  }

  package static func decodeInternal(
    _ payload: [UInt8]
  ) throws(DesignDatabaseRuntimeError) -> [DesignProjectionChildReference] {
    var reader = DesignProjectionByteReader(payload)
    let count = try reader.readCount()
    var children: [DesignProjectionChildReference] = []
    children.reserveCapacity(count)
    for _ in 0..<count {
      do {
        children.append(
          DesignProjectionChildReference(
            nodeDigest: try ContentDigest(
              algorithm: ContentDigestAlgorithm(rawValue: try reader.readString()),
              hexadecimalValue: try reader.readString()
            ),
            minimumKey: try DesignCanonicalKey(bytes: reader.readBytes()),
            maximumKey: try DesignCanonicalKey(bytes: reader.readBytes()),
            subtreeEntryCount: try reader.readUInt64(),
            subtreeNodeCount: try reader.readUInt64(),
            level: try reader.readUInt16()
          )
        )
      } catch let error as DesignDatabaseRuntimeError {
        throw error
      } catch {
        throw .persistedStateCorrupt(
          reason: "A projection internal node contains an invalid child reference."
        )
      }
    }
    try reader.requireExhausted()
    return children
  }

  private static func appendCount(
    _ count: Int,
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseRuntimeError) {
    guard let value = UInt32(exactly: count) else {
      throw .persistedStateCorrupt(
        reason: "A projection node item count exceeds the codec limit."
      )
    }
    append(value, to: &bytes)
  }

  private static func appendBytes(
    _ value: [UInt8],
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseRuntimeError) {
    guard let count = UInt32(exactly: value.count) else {
      throw .persistedStateCorrupt(
        reason: "A projection node field exceeds the codec limit."
      )
    }
    append(count, to: &bytes)
    bytes.append(contentsOf: value)
  }

  private static func appendString(
    _ value: String,
    to bytes: inout [UInt8]
  ) throws(DesignDatabaseRuntimeError) {
    try appendBytes(Array(value.utf8), to: &bytes)
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
    bytes.append(UInt8(truncatingIfNeeded: value >> 56))
    bytes.append(UInt8(truncatingIfNeeded: value >> 48))
    bytes.append(UInt8(truncatingIfNeeded: value >> 40))
    bytes.append(UInt8(truncatingIfNeeded: value >> 32))
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }
}

private struct DesignProjectionByteReader {
  private let bytes: [UInt8]
  private var offset = 0

  init(_ bytes: [UInt8]) {
    self.bytes = bytes
  }

  mutating func readCount() throws(DesignDatabaseRuntimeError) -> Int {
    guard let count = Int(exactly: try readUInt32()) else {
      throw .persistedStateCorrupt(
        reason: "A projection node count is outside the platform integer range."
      )
    }
    return count
  }

  mutating func readBytes() throws(DesignDatabaseRuntimeError) -> [UInt8] {
    let count = try readCount()
    guard count <= bytes.count - offset else {
      throw .persistedStateCorrupt(
        reason: "A projection node payload is truncated."
      )
    }
    defer { offset += count }
    return Array(bytes[offset..<(offset + count)])
  }

  mutating func readString() throws(DesignDatabaseRuntimeError) -> String {
    let value = try readBytes()
    guard let result = String(validating: value, as: UTF8.self) else {
      throw .persistedStateCorrupt(
        reason: "A projection node string is not valid UTF-8."
      )
    }
    return result
  }

  mutating func readUInt16() throws(DesignDatabaseRuntimeError) -> UInt16 {
    let value = try readFixed(count: 2)
    let start = value.startIndex
    return (UInt16(value[start]) << 8) | UInt16(value[start + 1])
  }

  mutating func readUInt32() throws(DesignDatabaseRuntimeError) -> UInt32 {
    let value = try readFixed(count: 4)
    let start = value.startIndex
    return (UInt32(value[start]) << 24)
      | (UInt32(value[start + 1]) << 16)
      | (UInt32(value[start + 2]) << 8)
      | UInt32(value[start + 3])
  }

  mutating func readUInt64() throws(DesignDatabaseRuntimeError) -> UInt64 {
    let value = try readFixed(count: 8)
    var result: UInt64 = 0
    for byte in value {
      result = (result << 8) | UInt64(byte)
    }
    return result
  }

  mutating func requireExhausted() throws(DesignDatabaseRuntimeError) {
    guard offset == bytes.count else {
      throw .persistedStateCorrupt(
        reason: "A projection node payload contains trailing bytes."
      )
    }
  }

  private mutating func readFixed(
    count: Int
  ) throws(DesignDatabaseRuntimeError) -> ArraySlice<UInt8> {
    guard count <= bytes.count - offset else {
      throw .persistedStateCorrupt(
        reason: "A projection node payload is truncated."
      )
    }
    defer { offset += count }
    return bytes[offset..<(offset + count)]
  }
}
