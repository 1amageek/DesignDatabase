import CircuiteFoundation

public enum DesignDisjointMergePublicationDigest {
  public static let canonicalVersion: UInt16 = 1

  public static func candidate(
    _ candidate: DesignDisjointMergeCandidate,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = Encoder(domain: "candidate")
    try encoder.append(candidate)
    return try digest(encoder.bytes, using: digester)
  }

  public static func request(
    operationID: DesignDatabaseOperationID,
    candidate: DesignDisjointMergeCandidate,
    validatedStateRevision: DesignRevisionReference,
    validatedStateCommit: DesignCommitSubmission,
    budget: DesignDisjointMergePublicationBudget,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = Encoder(domain: "request")
    try encoder.append(operationID.rawValue)
    try encoder.append(candidate)
    encoder.append(validatedStateRevision)
    try encoder.append(validatedStateCommit.operationID.rawValue)
    try encoder.append(validatedStateCommit.plan.planDigest)
    try encoder.append(validatedStateCommit.requestDigest)
    encoder.append(budget.maximumProjectionCount)
    encoder.append(budget.maximumPhysicalIdentityCount)
    return try digest(encoder.bytes, using: digester)
  }

  public static func changeSet(
    candidate: DesignDisjointMergeCandidate,
    validatedStateRevision: DesignRevisionReference,
    validatedStateCommitOperation: DesignDatabaseOperationReference,
    validatedStateCommitRequestDigest: ContentDigest,
    validatedStatePlanDigest: ContentDigest,
    stateDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = Encoder(domain: "change-set")
    try encoder.append(candidate)
    encoder.append(validatedStateRevision)
    try encoder.append(validatedStateCommitOperation)
    try encoder.append(validatedStateCommitRequestDigest)
    try encoder.append(validatedStatePlanDigest)
    try encoder.append(stateDigest)
    return try digest(encoder.bytes, using: digester)
  }

  public static func publishedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    candidateDigest: ContentDigest,
    candidateRevision: DesignRevisionReference,
    validatedStateRevision: DesignRevisionReference,
    validatedStateCommitOperation: DesignDatabaseOperationReference,
    validatedStateCommitRequestDigest: ContentDigest,
    validatedStatePlanDigest: ContentDigest,
    stateDigest: ContentDigest,
    changeSetDigest: ContentDigest,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = Encoder(domain: "outcome.published")
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(candidateDigest)
    encoder.append(candidateRevision)
    encoder.append(validatedStateRevision)
    try encoder.append(validatedStateCommitOperation)
    try encoder.append(validatedStateCommitRequestDigest)
    try encoder.append(validatedStatePlanDigest)
    try encoder.append(stateDigest)
    try encoder.append(changeSetDigest)
    return try digest(encoder.bytes, using: digester)
  }

  public static func rejectedOutcome(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    candidateDigest: ContentDigest,
    reason: DesignDisjointMergePublicationRejection.Reason,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseError) -> ContentDigest {
    var encoder = Encoder(domain: "outcome.rejected")
    try encoder.append(operation)
    try encoder.append(requestDigest)
    try encoder.append(candidateDigest)
    switch reason {
    case .assessmentChanged:
      encoder.append(UInt8(0))
    case .validatedStateMismatch:
      encoder.append(UInt8(1))
    case .candidateRevisionCollision(let revision):
      encoder.append(UInt8(2))
      encoder.append(revision)
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

private struct DesignDisjointMergePublicationDigestEncoder {
  private(set) var bytes: [UInt8] = []

  init(domain: String) {
    appendLiteral("DesignDatabase.DisjointMergePublication")
    append(DesignDisjointMergePublicationDigest.canonicalVersion)
    appendLiteral(domain)
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
    for shift in stride(from: 56, through: 0, by: -8) {
      bytes.append(UInt8((value >> UInt64(shift)) & 0xff))
    }
  }

  mutating func append(
    _ value: String
  ) throws(DesignDatabaseError) {
    guard let count = UInt32(exactly: value.utf8.count) else {
      throw .invalidMergeRequest(
        reason: "A canonical merge-publication string exceeds its limit."
      )
    }
    append(count)
    bytes.append(contentsOf: value.utf8)
  }

  mutating func append(_ digest: ContentDigest) throws(DesignDatabaseError) {
    try append(digest.algorithm.rawValue)
    try append(digest.hexadecimalValue)
  }

  mutating func append(_ revision: DesignRevisionReference) {
    appendLiteral(revision.databaseID.description)
    appendLiteral(revision.revisionID.description)
  }

  mutating func append(
    _ operation: DesignDatabaseOperationReference
  ) throws(DesignDatabaseError) {
    try append(operation.databaseID.description)
    try append(operation.authorizationSubjectScopeID.description)
    try append(operation.operationID.rawValue)
  }

  mutating func append(
    _ candidate: DesignDisjointMergeCandidate
  ) throws(DesignDatabaseError) {
    append(candidate.baseRevision)
    guard candidate.parentRevisions.count == 2 else {
      throw .invalidMergeRequest(
        reason: "A canonical merge publication requires two parents."
      )
    }
    for parent in candidate.parentRevisions { append(parent) }
    try append(candidate.designSchemaBundleDigest)
    try append(candidate.dependencyRootDigest)
    try append(candidate.semanticDependencyGraphDigest)
    try appendCount(candidate.facetRoots.count)
    for root in candidate.facetRoots {
      try append(root.facetID.rawValue)
      try append(root.digest)
    }
    try appendCount(candidate.leftChangedFacetIDs.count)
    for facetID in candidate.leftChangedFacetIDs {
      try append(facetID.rawValue)
    }
    try appendCount(candidate.rightChangedFacetIDs.count)
    for facetID in candidate.rightChangedFacetIDs {
      try append(facetID.rawValue)
    }
    try appendCount(candidate.semanticValidationRequirements.count)
    for requirement in candidate.semanticValidationRequirements {
      try append(requirement.kind.rawValue)
      try appendCount(requirement.facetIDs.count)
      for facetID in requirement.facetIDs {
        try append(facetID.rawValue)
      }
    }
    append(candidate.resourceReport.facetComparisonCount)
    append(candidate.resourceReport.ancestryRevisionReadCount)
    append(candidate.resourceReport.maximumFacetComparisonCount)
    append(candidate.resourceReport.maximumAncestryRevisionCount)
  }

  private mutating func appendCount(
    _ count: Int
  ) throws(DesignDatabaseError) {
    guard let value = UInt32(exactly: count) else {
      throw .invalidMergeRequest(
        reason: "A canonical merge-publication collection exceeds its limit."
      )
    }
    append(value)
  }

  private mutating func appendLiteral(_ value: String) {
    precondition(value.utf8.count <= Int(UInt32.max))
    append(UInt32(value.utf8.count))
    bytes.append(contentsOf: value.utf8)
  }
}

private typealias Encoder = DesignDisjointMergePublicationDigestEncoder
