import CircuiteFoundation

public enum DesignMutationPlanDigest {
  public static let canonicalVersion: UInt16 = 3

  public static func payload(
    _ payload: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    try digest(payload, using: digester)
  }

  public static func plan(
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    sourceEvidenceDigest: ContentDigest,
    budget: DesignMutationPlanBudget,
    segments: [DesignMutationPlanSegment],
    dependencyLockUpdate: DesignDependencyLockUpdate? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalMutationPlanByteEncoder(domain: .plan)
    encoder.append(databaseID)
    encoder.append(baseRevision)
    try encoder.append(designSchemaBundleDigest)
    try encoder.append(dependencyRootDigest)
    try encoder.append(semanticDependencyGraphDigest)
    try encoder.append(sourceEvidenceDigest)
    if let dependencyLockUpdate {
      encoder.append(UInt8(1))
      try encoder.append(dependencyLockUpdate.dependencyRootDigest)
      try encoder.append(
        dependencyLockUpdate.semanticDependencyGraphDigest
      )
    } else {
      encoder.append(UInt8(0))
    }
    encoder.append(budget)
    guard segments.count <= Int(UInt32.max) else {
      throw .invalidMutationPlan(reason: "The segment count exceeds the canonical limit.")
    }
    encoder.append(UInt32(segments.count))
    for segment in segments {
      try encoder.append(segment)
    }
    return try digest(encoder.bytes, using: digester)
  }

  public static func request(
    operationID: DesignDatabaseOperationID,
    planDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalMutationPlanByteEncoder(domain: .request)
    try encoder.append(operationID.rawValue)
    try encoder.append(planDigest)
    return try digest(encoder.bytes, using: digester)
  }

  public static func committedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    baseRevision: DesignRevisionReference,
    candidateRevision: DesignRevisionReference,
    stateDigest: ContentDigest,
    changeSetDigest: ContentDigest,
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalMutationPlanByteEncoder(domain: .committedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(planDigest)
    encoder.append(baseRevision)
    encoder.append(candidateRevision)
    try encoder.append(stateDigest)
    try encoder.append(changeSetDigest)
    try encoder.append(designSchemaBundleDigest)
    try encoder.append(dependencyRootDigest)
    try encoder.append(semanticDependencyGraphDigest)
    let canonicalFacetRoots = try DesignFacetRoot.canonicalizing(facetRoots)
    guard canonicalFacetRoots.count <= Int(UInt32.max) else {
      throw .invalidMutationPlan(
        reason: "The committed facet-root count exceeds the canonical limit."
      )
    }
    encoder.append(UInt32(canonicalFacetRoots.count))
    for root in canonicalFacetRoots {
      try encoder.append(root.facetID.rawValue)
      try encoder.append(root.digest)
    }
    return try digest(encoder.bytes, using: digester)
  }

  public static func rejectedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    planDigest: ContentDigest,
    reason: DesignCommitRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = CanonicalMutationPlanByteEncoder(domain: .rejectedOutcome)
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(planDigest)
    switch reason {
    case .baseRevisionNotFound(let revision):
      encoder.append(UInt8(0))
      encoder.append(revision)
    case .schemaBundleMismatch(let expected, let actual):
      encoder.append(UInt8(1))
      try encoder.append(expected)
      try encoder.append(actual)
    case .dependencyRootMismatch(let expected, let actual):
      encoder.append(UInt8(7))
      try encoder.append(expected)
      try encoder.append(actual)
    case .dependencyGraphMismatch(let expected, let actual):
      encoder.append(UInt8(8))
      try encoder.append(expected)
      try encoder.append(actual)
    case .adapterUnavailable(let schemaID, let adapterVersion):
      encoder.append(UInt8(2))
      try encoder.append(schemaID.rawValue)
      try encoder.append(adapterVersion)
    case .invalidSegmentPayload(let segmentID, let reason):
      encoder.append(UInt8(3))
      try encoder.append(segmentID.rawValue)
      try encoder.append(reason)
    case .validationFailed(_, let diagnosticsDigest):
      encoder.append(UInt8(4))
      try encoder.append(diagnosticsDigest)
    case .budgetExceeded(let limit, let requested):
      encoder.append(UInt8(5))
      encoder.append(limit)
      encoder.append(requested)
    case .candidateRevisionCollision(let revision):
      encoder.append(UInt8(6))
      encoder.append(revision)
    case .abandonedByMaintenance(
      let operation,
      let requestDigest,
      let reason,
      let evidenceDigest
    ):
      encoder.append(UInt8(9))
      try encoder.append(operation)
      try encoder.append(requestDigest)
      try encoder.append(reason.rawValue)
      try encoder.append(evidenceDigest)
    }
    return try digest(encoder.bytes, using: digester)
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    do {
      let count = UInt64(bytes.count)
      let limits = try ContentDigestSessionLimits(
        maximumChunkByteCount: max(count, 1),
        maximumTotalByteCount: max(count, 1),
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

private struct CanonicalMutationPlanByteEncoder {
  enum Domain: String {
    case plan
    case request
    case committedOutcome = "outcome.committed"
    case rejectedOutcome = "outcome.rejected"
  }

  private(set) var bytes: [UInt8] = []

  init(domain: Domain) {
    appendLiteral("DesignDatabase.MutationPlan")
    append(DesignMutationPlanDigest.canonicalVersion)
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
      throw .contentDigest("A canonical mutation-plan string exceeds the 32-bit limit.")
    }
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }

  mutating func append(_ value: DesignDatabaseID) {
    append(value.high)
    append(value.low)
  }

  mutating func append(_ value: DesignRevisionReference) {
    append(value.databaseID)
    append(value.revisionID.high)
    append(value.revisionID.low)
  }

  mutating func append(
    _ value: DesignDatabaseOperationReference
  ) throws(DesignDatabaseError) {
    append(value.databaseID)
    append(value.authorizationSubjectScopeID.high)
    append(value.authorizationSubjectScopeID.low)
    try append(value.operationID.rawValue)
  }

  mutating func append(_ value: ContentDigest) throws(DesignDatabaseError) {
    try append(value.algorithm.rawValue)
    try append(value.hexadecimalValue)
  }

  mutating func append(_ value: DesignMutationPlanBudget) {
    append(value.maximumSegmentCount)
    append(value.maximumPayloadByteCount)
    append(value.maximumPreparedWriteCount)
    append(value.maximumValidationReadCount)
  }

  mutating func append(
    _ value: DesignMutationPlanSegment
  ) throws(DesignDatabaseError) {
    try append(value.id.rawValue)
    try append(value.schemaID.rawValue)
    append(value.schemaVersion.major)
    append(value.schemaVersion.minor)
    append(value.schemaVersion.patch)
    try append(value.adapterVersion)
    try append(value.targetFacet.rawValue)
    guard let entityCount = UInt32(
      exactly: value.identityPlan.provisionalEntityIDs.count
    ), let occurrenceCount = UInt32(
      exactly: value.identityPlan.provisionalRelationOccurrenceIDs.count
    ) else {
      throw .invalidMutationPlan(
        reason: "A segment identity count exceeds the canonical limit."
      )
    }
    append(entityCount)
    for provisionalID in value.identityPlan.provisionalEntityIDs {
      try append(provisionalID.rawValue)
    }
    append(occurrenceCount)
    for provisionalID in value.identityPlan.provisionalRelationOccurrenceIDs {
      try append(provisionalID.rawValue)
    }
    try append(value.payloadDigest)
    append(UInt64(value.payload.count))
    append(value.expectedWriteCount)
  }

  private mutating func appendLiteral(_ value: String) {
    let encoded = value.utf8
    append(UInt32(encoded.count))
    bytes.append(contentsOf: encoded)
  }
}
