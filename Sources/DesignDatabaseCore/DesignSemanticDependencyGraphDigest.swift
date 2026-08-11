import CircuiteFoundation

public enum DesignSemanticDependencyGraphDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func root(
    _ identity: DesignSemanticDependencyGraphIdentity,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = SemanticGraphByteEncoder()
    try encoder.append(identity)
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

private struct SemanticGraphByteEncoder {
  private(set) var bytes: [UInt8] = []

  init() {
    appendLiteral("DesignDatabase.SemanticDependencyGraph")
    append(DesignSemanticDependencyGraphDigest.canonicalVersion)
  }

  mutating func append(
    _ identity: DesignSemanticDependencyGraphIdentity
  ) throws(DesignDatabaseError) {
    guard identity.nodes.count <= Int(UInt32.max),
          identity.edges.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "The semantic dependency graph exceeds its canonical 32-bit limits."
      )
    }
    append(UInt32(identity.nodes.count))
    for node in identity.nodes {
      try append(node.target)
      switch node.target {
      case .databaseRevision:
        guard let stateDigest = node.stateDigest,
              let schemaDigest = node.designSchemaBundleDigest else {
          throw .invalidDependencyLock(
            reason: "A canonical database dependency node is incomplete."
          )
        }
        try append(stateDigest)
        try append(schemaDigest)
      case .artifactContent:
        break
      }
    }
    append(UInt32(identity.edges.count))
    for edge in identity.edges {
      switch edge.source {
      case .root:
        append(UInt8(0))
      case .databaseRevision(let revision):
        append(UInt8(1))
        append(revision.databaseID.high)
        append(revision.databaseID.low)
        append(revision.revisionID.high)
        append(revision.revisionID.low)
      }
      try append(edge.dependency)
    }
  }

  mutating func append(
    _ entry: DesignDependencyLockEntry
  ) throws(DesignDatabaseError) {
    try append(entry.dependencyID.rawValue)
    try append(entry.semanticRole)
    try append(entry.target)
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

  mutating func append(
    _ target: DesignDependencyTarget
  ) throws(DesignDatabaseError) {
    switch target {
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
  }

  mutating func append(_ digest: ContentDigest) throws(DesignDatabaseError) {
    guard digest.algorithm == .sha256 else {
      throw .invalidDependencyLock(
        reason: "Every semantic dependency identity must use SHA-256."
      )
    }
    try append(digest.algorithm.rawValue)
    try append(digest.hexadecimalValue)
  }

  mutating func append(_ value: String) throws(DesignDatabaseError) {
    let encoded = value.utf8
    guard encoded.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "A semantic dependency token exceeds the canonical 32-bit limit."
      )
    }
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }

  mutating func append(_ value: [UInt8]) throws(DesignDatabaseError) {
    guard value.count <= Int(UInt32.max) else {
      throw .invalidDependencyLock(
        reason: "A semantic dependency identity exceeds the canonical 32-bit limit."
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
