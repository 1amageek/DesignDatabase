import CircuiteFoundation

public struct DesignRevisionDiff: Sendable, Hashable, DesignDatabaseSerializable {
  public let fromRevision: DesignRevisionReference
  public let toRevision: DesignRevisionReference
  public let stateChanged: Bool
  public let schemaChanged: Bool
  public let dependencyRootChanged: Bool
  public let semanticDependencyGraphChanged: Bool
  public let facetChanges: [DesignFacetChange]
  public let resourceReport: DesignRevisionDiffResourceReport

  public init(
    fromRevision: DesignRevisionReference,
    toRevision: DesignRevisionReference,
    stateChanged: Bool,
    schemaChanged: Bool,
    dependencyRootChanged: Bool,
    semanticDependencyGraphChanged: Bool,
    facetChanges: [DesignFacetChange],
    resourceReport: DesignRevisionDiffResourceReport
  ) {
    self.fromRevision = fromRevision
    self.toRevision = toRevision
    self.stateChanged = stateChanged
    self.schemaChanged = schemaChanged
    self.dependencyRootChanged = dependencyRootChanged
    self.semanticDependencyGraphChanged = semanticDependencyGraphChanged
    self.facetChanges = facetChanges.sorted()
    self.resourceReport = resourceReport
  }
}
