import CircuiteFoundation

public struct DesignRevisionDiffer: Sendable {
  public init() {}

  public func diff(
    from: DesignRevisionStateDescriptor,
    to: DesignRevisionStateDescriptor,
    budget: DesignRevisionDiffBudget
  ) throws(DesignDatabaseError) -> DesignRevisionDiff {
    guard from.revision.databaseID == to.revision.databaseID else {
      throw .crossDatabaseReference(
        expected: from.revision.databaseID,
        actual: to.revision.databaseID
      )
    }
    let fromByFacet = Dictionary(
      uniqueKeysWithValues: from.facetRoots.map { ($0.facetID, $0) }
    )
    let toByFacet = Dictionary(
      uniqueKeysWithValues: to.facetRoots.map { ($0.facetID, $0) }
    )
    let facetIDs = Set(fromByFacet.keys).union(toByFacet.keys).sorted {
      $0.rawValue < $1.rawValue
    }
    guard let comparisonCount = UInt64(exactly: facetIDs.count) else {
      throw .resourceExhausted(
        limit: budget.maximumFacetComparisonCount,
        requested: UInt64.max
      )
    }
    guard comparisonCount <= budget.maximumFacetComparisonCount else {
      throw .resourceExhausted(
        limit: budget.maximumFacetComparisonCount,
        requested: comparisonCount
      )
    }

    var changes: [DesignFacetChange] = []
    for facetID in facetIDs {
      let before = fromByFacet[facetID]
      let after = toByFacet[facetID]
      guard before != after else { continue }
      let kind: DesignFacetChangeKind
      switch (before, after) {
      case (nil, .some):
        kind = .added
      case (.some, nil):
        kind = .removed
      case (.some, .some):
        kind = .modified
      case (nil, nil):
        continue
      }
      changes.append(
        try DesignFacetChange(
          facetID: facetID,
          kind: kind,
          before: before,
          after: after
        )
      )
    }
    return DesignRevisionDiff(
      fromRevision: from.revision,
      toRevision: to.revision,
      stateChanged: from.stateDigest != to.stateDigest,
      schemaChanged: from.designSchemaBundleDigest
        != to.designSchemaBundleDigest,
      dependencyRootChanged: from.dependencyRootDigest
        != to.dependencyRootDigest,
      semanticDependencyGraphChanged: from.semanticDependencyGraphDigest
        != to.semanticDependencyGraphDigest,
      facetChanges: changes,
      resourceReport: DesignRevisionDiffResourceReport(
        facetComparisonCount: comparisonCount,
        maximumFacetComparisonCount: budget.maximumFacetComparisonCount
      )
    )
  }
}
