import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionSemanticAccumulator: Sendable, Hashable {
  package static let byteCount = 32

  package let first: [UInt8]
  package let second: [UInt8]

  package static var zero: Self {
    Self(
      first: Array(repeating: 0, count: byteCount),
      second: Array(repeating: 0, count: byteCount)
    )
  }

  package init(
    first: [UInt8],
    second: [UInt8]
  ) {
    precondition(first.count == Self.byteCount)
    precondition(second.count == Self.byteCount)
    self.first = first
    self.second = second
  }

  package static func make(
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    entries: [DesignProjectionEntry],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> Self {
    var result = Self.zero
    for entry in entries {
      result = try result.adding(
        entry,
        family: family,
        semanticVersion: semanticVersion,
        using: digester
      )
    }
    return result
  }

  package func adding(
    _ entry: DesignProjectionEntry,
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> Self {
    try applying(
      entry,
      operation: Self.add,
      family: family,
      semanticVersion: semanticVersion,
      using: digester
    )
  }

  package func removing(
    _ entry: DesignProjectionEntry,
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> Self {
    try applying(
      entry,
      operation: Self.subtract,
      family: family,
      semanticVersion: semanticVersion,
      using: digester
    )
  }

  package func sequenceDigest(
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    entryCount: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.ProjectionSemanticMapV2"
    )
    encoder.append(family.rawValue)
    encoder.append(semanticVersion.major)
    encoder.append(semanticVersion.minor)
    encoder.append(entryCount)
    encoder.append(first)
    encoder.append(second)
    return try encoder.finalize(using: digester)
  }

  private func applying(
    _ entry: DesignProjectionEntry,
    operation: ([UInt8], [UInt8]) -> [UInt8],
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> Self {
    let firstEntryDigest = try Self.entryDigest(
      domain: "DesignDatabase.ProjectionSemanticEntry.First",
      family: family,
      semanticVersion: semanticVersion,
      entry: entry,
      using: digester
    )
    let secondEntryDigest = try Self.entryDigest(
      domain: "DesignDatabase.ProjectionSemanticEntry.Second",
      family: family,
      semanticVersion: semanticVersion,
      entry: entry,
      using: digester
    )
    return Self(
      first: operation(first, firstEntryDigest),
      second: operation(second, secondEntryDigest)
    )
  }

  private static func entryDigest(
    domain: String,
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    entry: DesignProjectionEntry,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> [UInt8] {
    var encoder = DesignDatabaseRuntimeDigestEncoder(domain: domain)
    encoder.append(family.rawValue)
    encoder.append(semanticVersion.major)
    encoder.append(semanticVersion.minor)
    encoder.append(entry.key.bytes)
    encoder.append(entry.value)
    let digest = try encoder.finalize(using: digester)
    guard digest.algorithm == .sha256 else {
      throw .frameworkConfigurationFailed(
        reason: "Projection semantic accumulation requires SHA-256 digests."
      )
    }
    let bytes = try DesignProjectionTreeMaterialization.bytes(
      hexadecimal: digest.hexadecimalValue
    )
    guard bytes.count == byteCount else {
      throw .frameworkConfigurationFailed(
        reason: "Projection semantic accumulation received a non-256-bit digest."
      )
    }
    return bytes
  }

  private static func add(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
    var result = Array(repeating: UInt8(0), count: byteCount)
    var carry = 0
    for index in stride(from: byteCount - 1, through: 0, by: -1) {
      let value = Int(lhs[index]) + Int(rhs[index]) + carry
      result[index] = UInt8(truncatingIfNeeded: value)
      carry = value >> 8
    }
    return result
  }

  private static func subtract(
    _ lhs: [UInt8],
    _ rhs: [UInt8]
  ) -> [UInt8] {
    var result = Array(repeating: UInt8(0), count: byteCount)
    var borrow = 0
    for index in stride(from: byteCount - 1, through: 0, by: -1) {
      var value = Int(lhs[index]) - Int(rhs[index]) - borrow
      if value < 0 {
        value += 256
        borrow = 1
      } else {
        borrow = 0
      }
      result[index] = UInt8(value)
    }
    return result
  }
}
