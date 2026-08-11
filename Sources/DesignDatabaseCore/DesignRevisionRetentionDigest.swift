import CircuiteFoundation

public enum DesignRevisionRetentionDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func retainingRequest(
    operationID: DesignDatabaseOperationID,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    reason: DesignRevisionRetentionReason,
    evidenceDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalRetentionByteEncoder(domain: .retainingRequest)
    try encoder.append(operationID.rawValue)
    try encoder.append(claimID.rawValue)
    encoder.append(revision)
    try encoder.append(reason.rawValue)
    try encoder.append(evidenceDigest)
    return try digest(encoder.bytes, using: digester)
  }

  public static func releasingRequest(
    operationID: DesignDatabaseOperationID,
    claimID: DesignRevisionRetentionID,
    expectedRevision: DesignRevisionReference,
    expectedGeneration: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalRetentionByteEncoder(domain: .releasingRequest)
    try encoder.append(operationID.rawValue)
    try encoder.append(claimID.rawValue)
    encoder.append(expectedRevision)
    encoder.append(expectedGeneration)
    return try digest(encoder.bytes, using: digester)
  }

  public static func appliedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    claimID: DesignRevisionRetentionID,
    revision: DesignRevisionReference,
    generation: UInt64,
    reachabilityGeneration: UInt64,
    state: DesignRevisionRetentionState,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalRetentionByteEncoder(domain: .appliedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(claimID.rawValue)
    encoder.append(revision)
    encoder.append(generation)
    encoder.append(reachabilityGeneration)
    encoder.append(UInt8(state == .active ? 0 : 1))
    return try digest(encoder.bytes, using: digester)
  }

  public static func rejectedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    reason: DesignRevisionRetentionRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalRetentionByteEncoder(domain: .rejectedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    switch reason {
    case .operationRequestConflict:
      encoder.append(UInt8(0))
    case .claimUnavailable:
      encoder.append(UInt8(1))
    case .claimAlreadyActive:
      encoder.append(UInt8(2))
    case .claimPermanentlyReleased:
      encoder.append(UInt8(3))
    case .revisionNotFound:
      encoder.append(UInt8(4))
    case .revisionMismatch:
      encoder.append(UInt8(5))
    case .generationMismatch(let actual):
      encoder.append(UInt8(6))
      encoder.append(actual)
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

private struct CanonicalRetentionByteEncoder {
  enum Domain: String {
    case retainingRequest = "request.retain"
    case releasingRequest = "request.release"
    case appliedOutcome = "outcome.applied"
    case rejectedOutcome = "outcome.rejected"
  }

  private(set) var bytes: [UInt8] = []

  init(domain: Domain) {
    appendLiteral("DesignDatabase.Retention")
    append(DesignRevisionRetentionDigest.canonicalVersion)
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
    let bytes = value.utf8
    guard bytes.count <= Int(UInt32.max) else {
      throw .contentDigest("Canonical retention string exceeds the 32-bit byte limit.")
    }
    append(UInt32(bytes.count))
    self.bytes.append(contentsOf: bytes)
  }

  mutating func append(_ value: ContentDigest) throws(DesignDatabaseError) {
    try append(value.algorithm.rawValue)
    try append(value.hexadecimalValue)
  }

  mutating func append(_ value: DesignDatabaseOperationReference) throws(
    DesignDatabaseError
  ) {
    append(value.databaseID.high)
    append(value.databaseID.low)
    append(value.authorizationSubjectScopeID.high)
    append(value.authorizationSubjectScopeID.low)
    try append(value.operationID.rawValue)
  }

  mutating func append(_ value: DesignRevisionReference) {
    append(value.databaseID.high)
    append(value.databaseID.low)
    append(value.revisionID.high)
    append(value.revisionID.low)
  }

  private mutating func appendLiteral(_ value: String) {
    let bytes = value.utf8
    append(UInt32(bytes.count))
    self.bytes.append(contentsOf: bytes)
  }
}
