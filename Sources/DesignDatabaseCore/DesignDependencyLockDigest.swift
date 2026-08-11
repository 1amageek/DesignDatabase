import CircuiteFoundation

public enum DesignDependencyLockDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func root(
    _ lock: DesignDependencyLock,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = DependencyLockByteEncoder()
    guard lock.entries.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "The direct dependency count exceeds the canonical limit."
      )
    }
    encoder.append(UInt32(lock.entries.count))
    for entry in lock.entries {
      try encoder.append(entry)
    }
    do {
      let count = UInt64(encoder.bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(count, 1),
        maximumTotalByteCount: max(count, 1),
        maximumUpdateCount: 1
      )
      return try digester.digest(using: .sha256, limits: limits) {
        (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(encoder.bytes)
      }.digest
    } catch let error {
      throw .contentDigest(
        error.errorDescription ?? "Content digest failed without a description."
      )
    }
  }
}

private struct DependencyLockByteEncoder {
  private(set) var bytes: [UInt8] = []

  init() {
    appendLiteral("DesignDatabase.DirectDependencyLock")
    append(DesignDependencyLockDigest.canonicalVersion)
  }

  mutating func append(_ entry: DesignDependencyLockEntry) throws(DesignDatabaseError) {
    try append(entry.dependencyID.rawValue)
    try append(entry.semanticRole)
    switch entry.target {
    case .databaseRevision(let revision):
      append(UInt8(0))
      append(revision.databaseID.high)
      append(revision.databaseID.low)
      append(revision.revisionID.high)
      append(revision.revisionID.low)
    case .artifactContent(let artifactID):
      append(UInt8(1))
      try append(artifactID.canonicalBytes)
    }
    append(UInt32(entry.requiredSchemas.count))
    for schema in entry.requiredSchemas {
      try append(schema.schemaID.rawValue)
      append(schema.version.major)
      append(schema.version.minor)
      append(schema.version.patch)
      try append(schema.canonicalDigest)
    }
    append(UInt32(entry.requiredCapabilities.count))
    for capability in entry.requiredCapabilities {
      try append(capability.capabilityID.rawValue)
      append(capability.versions.lowerBound.major)
      append(capability.versions.lowerBound.minor)
      append(capability.versions.lowerBound.patch)
      append(capability.versions.upperBound.major)
      append(capability.versions.upperBound.minor)
      append(capability.versions.upperBound.patch)
      append(capability.necessity == .required ? UInt8(1) : UInt8(0))
    }
    try append(entry.interfaceDigest)
    try append(entry.retentionContractIdentity)
  }

  mutating func append(_ digest: ContentDigest) throws(DesignDatabaseError) {
    guard digest.algorithm == .sha256 else {
      throw .invalidDependencyLock(
        reason: "Every canonical dependency-lock digest must use SHA-256."
      )
    }
    try append(digest.algorithm.rawValue)
    try append(digest.hexadecimalValue)
  }

  mutating func append(_ value: String) throws(DesignDatabaseError) {
    let encoded = value.utf8
    guard encoded.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "A canonical dependency-lock token exceeds the 32-bit limit."
      )
    }
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }

  mutating func append(_ value: [UInt8]) throws(DesignDatabaseError) {
    guard value.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "A canonical dependency-lock identity exceeds the 32-bit limit."
      )
    }
    append(UInt32(value.count))
    bytes.append(contentsOf: value)
  }

  mutating func append(_ value: UInt8) {
    bytes.append(value)
  }

  mutating func append(_ value: UInt16) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  mutating func append(_ value: UInt32) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  mutating func append(_ value: UInt64) {
    bytes.append(UInt8(truncatingIfNeeded: value >> 56))
    bytes.append(UInt8(truncatingIfNeeded: value >> 48))
    bytes.append(UInt8(truncatingIfNeeded: value >> 40))
    bytes.append(UInt8(truncatingIfNeeded: value >> 32))
    bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    bytes.append(UInt8(truncatingIfNeeded: value >> 16))
    bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    bytes.append(UInt8(truncatingIfNeeded: value))
  }

  mutating func appendLiteral(_ value: String) {
    bytes.append(contentsOf: value.utf8)
    bytes.append(0)
  }
}
