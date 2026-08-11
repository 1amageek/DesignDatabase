import CircuiteFoundation

public enum DesignReferenceUpdateDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func request(
    operationID: DesignDatabaseOperationID,
    name: DesignReferenceName,
    expectedGeneration: UInt64,
    expectedRevision: DesignRevisionReference?,
    desiredRevision: DesignRevisionReference?,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalReferenceUpdateByteEncoder(domain: .request)
    try encoder.append(operationID.rawValue)
    try encoder.append(name.rawValue)
    encoder.append(expectedGeneration)
    encoder.append(expectedRevision)
    encoder.append(desiredRevision)
    return try digest(encoder.bytes, using: digester)
  }

  public static func appliedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    name: DesignReferenceName,
    previousRevision: DesignRevisionReference?,
    currentRevision: DesignRevisionReference?,
    generation: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalReferenceUpdateByteEncoder(domain: .appliedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(name.rawValue)
    encoder.append(previousRevision)
    encoder.append(currentRevision)
    encoder.append(generation)
    return try digest(encoder.bytes, using: digester)
  }

  public static func rejectedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    name: DesignReferenceName,
    reason: DesignReferenceUpdateRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalReferenceUpdateByteEncoder(domain: .rejectedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(name.rawValue)
    switch reason {
    case .preconditionMismatch(let generation, let revision):
      encoder.append(UInt8(0))
      encoder.append(generation)
      encoder.append(revision)
    case .desiredRevisionNotFound(let revision):
      encoder.append(UInt8(1))
      encoder.append(revision)
    }
    return try digest(encoder.bytes, using: digester)
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    do {
      let byteCount = UInt64(bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(byteCount, 1),
        maximumTotalByteCount: max(byteCount, 1),
        maximumUpdateCount: 1
      )
      return try digester.digest(using: .sha256, limits: limits) {
        (lease: borrowing ContentDigestUpdateLease) throws(ContentDigestError) in
        try lease.update(bytes)
      }.digest
    } catch let error {
      throw .contentDigest(
        error.errorDescription ?? "Content digest failed without a description."
      )
    }
  }
}

private struct CanonicalReferenceUpdateByteEncoder {
  enum Domain: String {
    case request
    case appliedOutcome
    case rejectedOutcome
  }

  private(set) var bytes: [UInt8] = []

  init(domain: Domain) {
    appendLiteral("DesignDatabase.ReferenceUpdate")
    append(DesignReferenceUpdateDigest.canonicalVersion)
    appendLiteral(domain.rawValue)
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

  mutating func append(_ value: String) throws(DesignDatabaseError) {
    let encoded = value.utf8
    guard encoded.count <= Int(UInt32.max) else {
      throw .contentDigest("Canonical reference-update string exceeds the 32-bit byte limit.")
    }
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }

  mutating func append(_ value: ContentDigest) throws(DesignDatabaseError) {
    try append(value.algorithm.rawValue)
    try append(value.hexadecimalValue)
  }

  mutating func append(
    _ value: DesignDatabaseOperationReference
  ) throws(DesignDatabaseError) {
    append(value.databaseID.high)
    append(value.databaseID.low)
    append(value.authorizationSubjectScopeID.high)
    append(value.authorizationSubjectScopeID.low)
    try append(value.operationID.rawValue)
  }

  mutating func append(_ value: DesignRevisionReference?) {
    guard let value else {
      append(UInt8(0))
      return
    }
    append(UInt8(1))
    append(value.databaseID.high)
    append(value.databaseID.low)
    append(value.revisionID.high)
    append(value.revisionID.low)
  }

  private mutating func appendLiteral(_ value: String) {
    let encoded = value.utf8
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }
}
