import CircuiteFoundation
import DesignDatabaseCore
import Foundation
import Testing

@Suite
struct DesignRevisionAnalysisTests {
  @Test
  func arbitraryRevisionDiffComparesCompleteFacetRootState() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 1)
    let from = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      stateByte: "10",
      roots: [
        try root("logic", "11"),
        try root("timing", "12"),
      ]
    )
    let to = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      stateByte: "20",
      dependencyByte: "21",
      roots: [
        try root("logic", "22"),
        try root("layout", "23"),
      ]
    )

    let result = try DesignRevisionDiffer().diff(
      from: from,
      to: to,
      budget: DesignRevisionDiffBudget(maximumFacetComparisonCount: 3)
    )

    #expect(result.fromRevision == from.revision)
    #expect(result.toRevision == to.revision)
    #expect(result.stateChanged)
    #expect(!result.schemaChanged)
    #expect(result.dependencyRootChanged)
    #expect(!result.semanticDependencyGraphChanged)
    #expect(result.facetChanges.map(\.facetID.rawValue) == [
      "layout", "logic", "timing",
    ])
    #expect(result.facetChanges.map(\.kind) == [
      .added, .modified, .removed,
    ])
    #expect(result.resourceReport.facetComparisonCount == 3)
  }

  @Test
  func arbitraryRevisionDiffRejectsFacetWorkBeyondBudget() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let from = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11"), try root("timing", "12")]
    )
    let to = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      roots: [try root("layout", "13")]
    )

    do {
      _ = try DesignRevisionDiffer().diff(
        from: from,
        to: to,
        budget: DesignRevisionDiffBudget(maximumFacetComparisonCount: 2)
      )
      Issue.record("The diff exceeded its facet-comparison budget.")
    } catch let error {
      #expect(error == .resourceExhausted(limit: 2, requested: 3))
    }
  }

  @Test
  func disjointFacetChangesRequireSemanticValidation() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 3)
    let base = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11"), try root("layout", "12")]
    )
    let left = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      stateByte: "20",
      roots: [try root("logic", "21"), try root("layout", "12")]
    )
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision],
      stateByte: "30",
      roots: [try root("logic", "11"), try root("layout", "31")]
    )
    let budget = try DesignDisjointMergeBudget(
      maximumFacetComparisonCount: 2,
      maximumAncestryRevisionCount: 3
    )

    let assessment = try DesignDisjointMergeAssessor().assess(
      base: base,
      left: left,
      right: right,
      baseIsAncestorOfLeft: true,
      baseIsAncestorOfRight: true,
      ancestryRevisionReadCount: 3,
      budget: budget
    )
    guard case .requiresSemanticValidation(let candidate) = assessment else {
      Issue.record("A disjoint merge was not handed to semantic validation.")
      return
    }
    #expect(candidate.baseRevision == base.revision)
    #expect(candidate.parentRevisions == [left.revision, right.revision])
    #expect(candidate.facetRoots == [
      try root("layout", "31"),
      try root("logic", "21"),
    ])
    #expect(candidate.leftChangedFacetIDs.map(\.rawValue) == ["logic"])
    #expect(candidate.rightChangedFacetIDs.map(\.rawValue) == ["layout"])
    #expect(candidate.semanticValidationRequirements.map(\.kind) == [
      .crossFacetComposite,
    ])
    #expect(candidate.resourceReport.facetComparisonCount == 2)
    #expect(candidate.resourceReport.ancestryRevisionReadCount == 3)
  }

  @Test
  func disjointMergeStateIsIndependentOfSideOrdering() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 4)
    let base = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11"), try root("layout", "12")]
    )
    let left = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      roots: [try root("logic", "21"), try root("layout", "12")]
    )
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision],
      roots: [try root("logic", "11"), try root("layout", "31")]
    )
    let budget = try DesignDisjointMergeBudget(
      maximumFacetComparisonCount: 2,
      maximumAncestryRevisionCount: 3
    )
    let forward = try mergeCandidate(
      base: base,
      left: left,
      right: right,
      budget: budget
    )
    let reversed = try mergeCandidate(
      base: base,
      left: right,
      right: left,
      budget: budget
    )

    #expect(forward.parentRevisions == reversed.parentRevisions)
    #expect(forward.facetRoots == reversed.facetRoots)
    #expect(forward.designSchemaBundleDigest == reversed.designSchemaBundleDigest)
    #expect(forward.dependencyRootDigest == reversed.dependencyRootDigest)
    #expect(
      forward.semanticDependencyGraphDigest
        == reversed.semanticDependencyGraphDigest
    )
    #expect(forward.leftChangedFacetIDs == reversed.leftChangedFacetIDs)
    #expect(forward.rightChangedFacetIDs == reversed.rightChangedFacetIDs)
    #expect(
      forward.semanticValidationRequirements
        == reversed.semanticValidationRequirements
    )
    #expect(forward == reversed)
  }

  @Test
  func disjointMergeConflictIsIndependentOfSideOrdering() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 40)
    let base = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11")]
    )
    let left = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision],
      roots: [try root("logic", "31")]
    )
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      roots: [try root("logic", "21")]
    )

    let forward = try assess(base: base, left: left, right: right)
    let reversed = try assess(base: base, left: right, right: left)

    #expect(forward == reversed)
    guard case .conflict(let conflict) = forward else {
      Issue.record("The deterministic conflict fixture produced a merge candidate.")
      return
    }
    #expect(conflict.revisions == [
      base.revision,
      right.revision,
      left.revision,
    ])
  }

  @Test
  func overlappingFacetChangesProduceTypedConflict() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 5)
    let base = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11")]
    )
    let left = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      roots: [try root("logic", "21")]
    )
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision],
      roots: [try root("logic", "31")]
    )

    let assessment = try assess(base: base, left: left, right: right)
    guard case .conflict(let conflict) = assessment else {
      Issue.record("Divergent changes to one facet were not rejected.")
      return
    }
    #expect(conflict.kind == .overlappingFacetChange)
    #expect(conflict.facetIDs.map(\.rawValue) == ["logic"])
  }

  @Test
  func schemaAndDependencyDivergenceProduceTypedConflicts() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 6)
    let base = try descriptor(databaseID: databaseID, revisionLow: 1)
    let schemaLeft = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      schemaByte: "21"
    )
    let schemaRight = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision]
    )
    let schemaAssessment = try assess(
      base: base,
      left: schemaLeft,
      right: schemaRight
    )
    guard case .conflict(let schemaConflict) = schemaAssessment else {
      Issue.record("Schema divergence was not rejected.")
      return
    }
    #expect(schemaConflict.kind == .schemaDivergence)

    let dependencyLeft = try descriptor(
      databaseID: databaseID,
      revisionLow: 4,
      parents: [base.revision],
      dependencyByte: "41"
    )
    let dependencyRight = try descriptor(
      databaseID: databaseID,
      revisionLow: 5,
      parents: [base.revision],
      dependencyByte: "51"
    )
    let dependencyAssessment = try assess(
      base: base,
      left: dependencyLeft,
      right: dependencyRight
    )
    guard case .conflict(let dependencyConflict) = dependencyAssessment else {
      Issue.record("Dependency-root divergence was not rejected.")
      return
    }
    #expect(dependencyConflict.kind == .dependencyRootDivergence)
  }

  @Test
  func declaredBaseMustBeAnAncestorOfBothSides() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 7)
    let base = try descriptor(databaseID: databaseID, revisionLow: 1)
    let left = try descriptor(databaseID: databaseID, revisionLow: 2)
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision]
    )
    let budget = try DesignDisjointMergeBudget(
      maximumFacetComparisonCount: 1,
      maximumAncestryRevisionCount: 3
    )

    let assessment = try DesignDisjointMergeAssessor().assess(
      base: base,
      left: left,
      right: right,
      baseIsAncestorOfLeft: false,
      baseIsAncestorOfRight: true,
      ancestryRevisionReadCount: 3,
      budget: budget
    )
    guard case .conflict(let conflict) = assessment else {
      Issue.record("A non-ancestor merge base was accepted.")
      return
    }
    #expect(conflict.kind == .baseNotAncestor)
    #expect(conflict.revisions == [base.revision, left.revision])
  }

  @Test
  func decodedRevisionAnalysisInputsReapplyPublicInvariants() throws {
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignRevisionDiffBudget.self,
        from: Data(#"{"maximumFacetComparisonCount":0}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDisjointMergeBudget.self,
        from: Data(
          #"{"maximumFacetComparisonCount":1,"maximumAncestryRevisionCount":0}"#.utf8
        )
      )
    }
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDisjointMergePublicationBudget.self,
        from: Data(
          #"{"maximumProjectionCount":0,"maximumPhysicalIdentityCount":1}"#.utf8
        )
      )
    }

    let databaseID = try DesignDatabaseID(high: 1, low: 8)
    let base = try descriptor(
      databaseID: databaseID,
      revisionLow: 1,
      roots: [try root("logic", "11"), try root("layout", "12")]
    )
    let left = try descriptor(
      databaseID: databaseID,
      revisionLow: 2,
      parents: [base.revision],
      roots: [try root("logic", "21"), try root("layout", "12")]
    )
    let right = try descriptor(
      databaseID: databaseID,
      revisionLow: 3,
      parents: [base.revision],
      roots: [try root("logic", "11"), try root("layout", "31")]
    )
    let candidate = try mergeCandidate(
      base: base,
      left: left,
      right: right,
      budget: DesignDisjointMergeBudget(
        maximumFacetComparisonCount: 2,
        maximumAncestryRevisionCount: 3
      )
    )
    var candidateObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(candidate)
      ) as? [String: Any]
    )
    let parentObjects = try #require(
      candidateObject["parentRevisions"] as? [Any]
    )
    candidateObject["parentRevisions"] = [try #require(parentObjects.first)]
    let malformedCandidate = try JSONSerialization.data(
      withJSONObject: candidateObject,
      options: [.sortedKeys]
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDisjointMergeCandidate.self,
        from: malformedCandidate
      )
    }

    let planBudget = try DesignMutationPlanBudget(
      maximumSegmentCount: 1,
      maximumPayloadByteCount: 1,
      maximumPreparedWriteCount: 1,
      maximumValidationReadCount: 1
    )
    let planDigest = try digest("51")
    let plan = DesignMutationPlan(
      databaseID: databaseID,
      baseRevision: left.revision,
      designSchemaBundleDigest: candidate.designSchemaBundleDigest,
      dependencyRootDigest: candidate.dependencyRootDigest,
      semanticDependencyGraphDigest:
        candidate.semanticDependencyGraphDigest,
      sourceEvidenceDigest: try digest("52"),
      budget: planBudget,
      segments: [],
      planDigest: planDigest
    )
    let validationCommit = DesignCommitSubmission(
      operationID: try DesignDatabaseOperationID(
        rawValue: "decode-validation-commit"
      ),
      plan: plan,
      requestDigest: try digest("53")
    )
    let publication = try DesignDisjointMergePublicationSubmission(
      operationID: DesignDatabaseOperationID(
        rawValue: "decode-merge-publication"
      ),
      candidate: candidate,
      validatedStateRevision: left.revision,
      validatedStateCommit: validationCommit,
      budget: DesignDisjointMergePublicationBudget(
        maximumProjectionCount: 1,
        maximumPhysicalIdentityCount: 1
      ),
      requestDigest: try digest("54")
    )
    var publicationObject = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(publication)
      ) as? [String: Any]
    )
    publicationObject["schemaVersion"] = 2
    let unsupportedPublication = try JSONSerialization.data(
      withJSONObject: publicationObject,
      options: [.sortedKeys]
    )
    #expect(throws: DecodingError.self) {
      _ = try JSONDecoder().decode(
        DesignDisjointMergePublicationSubmission.self,
        from: unsupportedPublication
      )
    }
  }

  private func assess(
    base: DesignRevisionStateDescriptor,
    left: DesignRevisionStateDescriptor,
    right: DesignRevisionStateDescriptor
  ) throws -> DesignDisjointMergeAssessment {
    try DesignDisjointMergeAssessor().assess(
      base: base,
      left: left,
      right: right,
      baseIsAncestorOfLeft: true,
      baseIsAncestorOfRight: true,
      ancestryRevisionReadCount: 3,
      budget: DesignDisjointMergeBudget(
        maximumFacetComparisonCount: 16,
        maximumAncestryRevisionCount: 16
      )
    )
  }

  private func mergeCandidate(
    base: DesignRevisionStateDescriptor,
    left: DesignRevisionStateDescriptor,
    right: DesignRevisionStateDescriptor,
    budget: DesignDisjointMergeBudget
  ) throws -> DesignDisjointMergeCandidate {
    let assessment = try DesignDisjointMergeAssessor().assess(
      base: base,
      left: left,
      right: right,
      baseIsAncestorOfLeft: true,
      baseIsAncestorOfRight: true,
      ancestryRevisionReadCount: 3,
      budget: budget
    )
    guard case .requiresSemanticValidation(let candidate) = assessment else {
      throw DesignDatabaseError.invalidMergeRequest(
        reason: "The test fixture did not produce a merge candidate."
      )
    }
    return candidate
  }

  private func descriptor(
    databaseID: DesignDatabaseID,
    revisionLow: UInt64,
    parents: [DesignRevisionReference] = [],
    stateByte: String = "10",
    schemaByte: String = "11",
    dependencyByte: String = "12",
    semanticGraphByte: String = "13",
    roots: [DesignFacetRoot] = []
  ) throws -> DesignRevisionStateDescriptor {
    try DesignRevisionStateDescriptor(
      revision: DesignRevisionReference(
        databaseID: databaseID,
        revisionID: DesignRevisionID(high: 0, low: revisionLow)
      ),
      parents: parents,
      stateDigest: digest(stateByte),
      designSchemaBundleDigest: digest(schemaByte),
      dependencyRootDigest: digest(dependencyByte),
      semanticDependencyGraphDigest: digest(semanticGraphByte),
      facetRoots: roots,
      directChangeRootDigest: digest("14")
    )
  }

  private func root(
    _ facetID: String,
    _ byte: String
  ) throws -> DesignFacetRoot {
    try DesignFacetRoot(
      facetID: DesignFacetID(rawValue: facetID),
      digest: digest(byte)
    )
  }

  private func digest(_ byte: String) throws -> ContentDigest {
    try ContentDigest(
      algorithm: .sha256,
      hexadecimalValue: String(repeating: byte, count: 32)
    )
  }
}
