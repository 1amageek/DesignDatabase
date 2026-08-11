import CircuiteFoundation

public enum DesignCommitAbandonmentDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func request(
    operationID: DesignDatabaseOperationID,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    reason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalCommitAbandonmentByteEncoder(domain: .request)
    try encoder.append(operationID.rawValue)
    try encoder.append(targetOperation)
    try encoder.append(targetRequestDigest)
    try encoder.append(reason.rawValue)
    try encoder.append(evidenceDigest)
    return try digest(encoder.bytes, using: digester)
  }

  public static func abandonedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    reason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    targetCommitOutcomeDigest: ContentDigest,
    stagingRootTerminalized: Bool,
    reachabilityGeneration: UInt64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalCommitAbandonmentByteEncoder(
      domain: .abandonedOutcome
    )
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(targetOperation)
    try encoder.append(targetRequestDigest)
    try encoder.append(reason.rawValue)
    try encoder.append(evidenceDigest)
    try encoder.append(targetCommitOutcomeDigest)
    encoder.append(UInt8(stagingRootTerminalized ? 1 : 0))
    encoder.append(reachabilityGeneration)
    return try digest(encoder.bytes, using: digester)
  }

  public static func rejectedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    targetOperation: DesignDatabaseOperationReference,
    targetRequestDigest: ContentDigest,
    abandonmentReason: DesignCommitAbandonmentReason,
    evidenceDigest: ContentDigest,
    reason: DesignCommitAbandonmentRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalCommitAbandonmentByteEncoder(
      domain: .rejectedOutcome
    )
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(targetOperation)
    try encoder.append(targetRequestDigest)
    try encoder.append(abandonmentReason.rawValue)
    try encoder.append(evidenceDigest)
    switch reason {
    case .targetNotRecorded:
      encoder.append(UInt8(0))
    case .targetOperationKindMismatch:
      encoder.append(UInt8(1))
    case .targetRequestMismatch(let actual):
      encoder.append(UInt8(2))
      try encoder.append(actual)
    case .targetAlreadyCommitted(let outcomeDigest):
      encoder.append(UInt8(3))
      try encoder.append(outcomeDigest)
    case .targetAlreadyRejected(let outcomeDigest):
      encoder.append(UInt8(4))
      try encoder.append(outcomeDigest)
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

private struct CanonicalCommitAbandonmentByteEncoder {
  enum Domain: String {
    case request
    case abandonedOutcome = "outcome.abandoned"
    case rejectedOutcome = "outcome.rejected"
  }

  private(set) var bytes: [UInt8] = []

  init(domain: Domain) {
    appendLiteral("DesignDatabase.CommitAbandonment")
    append(DesignCommitAbandonmentDigest.canonicalVersion)
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
      throw .contentDigest(
        "Canonical commit-abandonment string exceeds the 32-bit byte limit."
      )
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

  private mutating func appendLiteral(_ value: String) {
    let encoded = value.utf8
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }
}
