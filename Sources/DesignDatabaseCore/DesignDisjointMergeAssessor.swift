import CircuiteFoundation

public struct DesignDisjointMergeAssessor: Sendable {
  public init() {}

  public func assess(
    base: DesignRevisionStateDescriptor,
    left: DesignRevisionStateDescriptor,
    right: DesignRevisionStateDescriptor,
    baseIsAncestorOfLeft: Bool,
    baseIsAncestorOfRight: Bool,
    ancestryRevisionReadCount: UInt64,
    budget: DesignDisjointMergeBudget
  ) throws(DesignDatabaseError) -> DesignDisjointMergeAssessment {
    try validateDatabaseIdentity(base: base, left: left, right: right)
    let facetIDs = Set(base.facetRoots.map { $0.facetID })
      .union(left.facetRoots.map { $0.facetID })
      .union(right.facetRoots.map { $0.facetID })
      .sorted { $0.rawValue < $1.rawValue }
    guard let facetComparisonCount = UInt64(exactly: facetIDs.count) else {
      throw .resourceExhausted(
        limit: budget.maximumFacetComparisonCount,
        requested: UInt64.max
      )
    }
    guard facetComparisonCount <= budget.maximumFacetComparisonCount else {
      throw .resourceExhausted(
        limit: budget.maximumFacetComparisonCount,
        requested: facetComparisonCount
      )
    }
    guard ancestryRevisionReadCount <= budget.maximumAncestryRevisionCount else {
      throw .resourceExhausted(
        limit: budget.maximumAncestryRevisionCount,
        requested: ancestryRevisionReadCount
      )
    }
    let report = DesignDisjointMergeResourceReport(
      facetComparisonCount: facetComparisonCount,
      ancestryRevisionReadCount: ancestryRevisionReadCount,
      maximumFacetComparisonCount: budget.maximumFacetComparisonCount,
      maximumAncestryRevisionCount: budget.maximumAncestryRevisionCount
    )
    let revisions = [base.revision] + [left.revision, right.revision].sorted {
      $0.revisionID.description < $1.revisionID.description
    }
    guard baseIsAncestorOfLeft, baseIsAncestorOfRight else {
      let nonDescendants = [
        baseIsAncestorOfLeft ? nil : left.revision,
        baseIsAncestorOfRight ? nil : right.revision,
      ].compactMap { $0 }.sorted {
        $0.revisionID.description < $1.revisionID.description
      }
      return .conflict(
        DesignDisjointMergeConflict(
          kind: .baseNotAncestor,
          revisions: [base.revision] + nonDescendants,
          reason: "The declared base is not an ancestor of every merge side.",
          resourceReport: report
        )
      )
    }
    guard base.designSchemaBundleDigest == left.designSchemaBundleDigest,
          base.designSchemaBundleDigest == right.designSchemaBundleDigest else {
      return .conflict(
        DesignDisjointMergeConflict(
          kind: .schemaDivergence,
          revisions: revisions,
          reason: "A deterministic disjoint merge cannot cross a schema migration.",
          resourceReport: report
        )
      )
    }
    guard let dependencyRoot = threeWayValue(
      base: base.dependencyRootDigest,
      left: left.dependencyRootDigest,
      right: right.dependencyRootDigest
    ) else {
      return .conflict(
        DesignDisjointMergeConflict(
          kind: .dependencyRootDivergence,
          revisions: revisions,
          reason: "Both merge sides changed the exact dependency root differently.",
          resourceReport: report
        )
      )
    }
    guard let semanticGraph = threeWayValue(
      base: base.semanticDependencyGraphDigest,
      left: left.semanticDependencyGraphDigest,
      right: right.semanticDependencyGraphDigest
    ) else {
      return .conflict(
        DesignDisjointMergeConflict(
          kind: .semanticDependencyGraphDivergence,
          revisions: revisions,
          reason: "Both merge sides changed the semantic dependency graph differently.",
          resourceReport: report
        )
      )
    }

    let baseRoots = Dictionary(
      uniqueKeysWithValues: base.facetRoots.map { ($0.facetID, $0) }
    )
    let leftRoots = Dictionary(
      uniqueKeysWithValues: left.facetRoots.map { ($0.facetID, $0) }
    )
    let rightRoots = Dictionary(
      uniqueKeysWithValues: right.facetRoots.map { ($0.facetID, $0) }
    )
    var mergedRoots: [DesignFacetRoot] = []
    var leftChanged: [DesignFacetID] = []
    var rightChanged: [DesignFacetID] = []
    var conflicts: [DesignFacetID] = []
    for facetID in facetIDs {
      let baseRoot = baseRoots[facetID]
      let leftRoot = leftRoots[facetID]
      let rightRoot = rightRoots[facetID]
      if leftRoot != baseRoot { leftChanged.append(facetID) }
      if rightRoot != baseRoot { rightChanged.append(facetID) }
      guard let merged = threeWayValue(
        base: baseRoot,
        left: leftRoot,
        right: rightRoot
      ) else {
        conflicts.append(facetID)
        continue
      }
      if let merged { mergedRoots.append(merged) }
    }
    guard conflicts.isEmpty else {
      return .conflict(
        DesignDisjointMergeConflict(
          kind: .overlappingFacetChange,
          revisions: revisions,
          facetIDs: conflicts,
          reason: "Both merge sides changed the same facet to different exact roots.",
          resourceReport: report
        )
      )
    }

    let changedFacetIDs = Set(leftChanged).union(rightChanged).sorted {
      $0.rawValue < $1.rawValue
    }
    var requirements = [
      DesignDisjointMergeSemanticValidationRequirement(
        kind: .crossFacetComposite,
        facetIDs: changedFacetIDs
      ),
    ]
    if dependencyRoot != base.dependencyRootDigest
        || semanticGraph != base.semanticDependencyGraphDigest {
      requirements.append(
        DesignDisjointMergeSemanticValidationRequirement(
          kind: .dependencyBinding,
          facetIDs: mergedRoots.map { $0.facetID }
        )
      )
    }
    return .requiresSemanticValidation(
      try DesignDisjointMergeCandidate(
        baseRevision: base.revision,
        parentRevisions: [left.revision, right.revision],
        designSchemaBundleDigest: base.designSchemaBundleDigest,
        dependencyRootDigest: dependencyRoot,
        semanticDependencyGraphDigest: semanticGraph,
        facetRoots: mergedRoots,
        leftChangedFacetIDs: leftChanged,
        rightChangedFacetIDs: rightChanged,
        semanticValidationRequirements: requirements,
        resourceReport: report
      )
    )
  }

  private func validateDatabaseIdentity(
    base: DesignRevisionStateDescriptor,
    left: DesignRevisionStateDescriptor,
    right: DesignRevisionStateDescriptor
  ) throws(DesignDatabaseError) {
    guard left.revision.databaseID == base.revision.databaseID else {
      throw .crossDatabaseReference(
        expected: base.revision.databaseID,
        actual: left.revision.databaseID
      )
    }
    guard right.revision.databaseID == base.revision.databaseID else {
      throw .crossDatabaseReference(
        expected: base.revision.databaseID,
        actual: right.revision.databaseID
      )
    }
  }

  private func threeWayValue<Value: Equatable>(
    base: Value,
    left: Value,
    right: Value
  ) -> Value? {
    if left == right { return left }
    if left == base { return right }
    if right == base { return left }
    return nil
  }
}
