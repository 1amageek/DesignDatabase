import CircuiteFoundation

package struct DesignDatabaseRuntimeDigestEncoder {
  private var bytes: [UInt8] = []

  package init(domain: String, formatVersion: UInt16 = 1) {
    append(domain)
    append(formatVersion)
  }

  package mutating func append(_ value: UInt16) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  package mutating func append(_ value: UInt32) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  package mutating func append(_ value: UInt64) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 56))
    bytes.append(UInt8(truncatingIfNeeded: value >> 48))
    bytes.append(UInt8(truncatingIfNeeded: value >> 40))
    bytes.append(UInt8(truncatingIfNeeded: value >> 32))
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  package mutating func append(_ value: String) {
    let encoded = Array(value.utf8)
    precondition(encoded.count <= Int(UInt32.max))
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }

  package mutating func append(_ value: [UInt8]) {
    precondition(value.count <= Int(UInt32.max))
    append(UInt32(value.count))
    bytes.append(contentsOf: value)
  }

  package mutating func append(_ digest: ContentDigest) {
    append(digest.algorithm.rawValue)
    append(digest.hexadecimalValue)
  }

  package func finalize(
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    do {
      let byteCount = UInt64(bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(byteCount, 1),
        maximumTotalByteCount: max(byteCount, 1),
        maximumUpdateCount: 1
      )
      let result = try digester.digest(
        using: .sha256,
        limits: limits
      ) { (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(bytes)
      }
      return result.digest
    } catch {
      throw .registrationDigestFailed(reason: String(describing: error))
    }
  }
}
