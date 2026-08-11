import CircuiteFoundation

public struct DesignRelationSchema: Sendable, Hashable, DesignDatabaseSerializable {
  public let id: DesignRelationKindID
  public let targetFacets: Set<DesignFacetID>
  public let isHierarchyParent: Bool
  public let isConnectivity: Bool
  public let isCrossFacet: Bool
  public let isDependency: Bool

  public init(
    id: DesignRelationKindID,
    targetFacets: Set<DesignFacetID> = [],
    isHierarchyParent: Bool = false,
    isConnectivity: Bool = false,
    isCrossFacet: Bool = false,
    isDependency: Bool = false
  ) {
    self.id = id
    self.targetFacets = targetFacets
    self.isHierarchyParent = isHierarchyParent
    self.isConnectivity = isConnectivity
    self.isCrossFacet = isCrossFacet
    self.isDependency = isDependency
  }
}
