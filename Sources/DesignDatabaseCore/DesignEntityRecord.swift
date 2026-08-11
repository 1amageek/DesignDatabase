import CircuiteFoundation

public struct DesignEntityRecord: Sendable, Hashable, DesignDatabaseSerializable {
  public let key: DesignEntityKey
  public let facetID: DesignFacetID
  public let kindID: DesignEntityKindID
  public var fields: [DesignFieldID: DesignValue]
  public var relations: [DesignRelationKindID: Set<DesignEntityID>]
  public var spatialEntries: [DesignSpatialEntry]

  public init(
    key: DesignEntityKey,
    facetID: DesignFacetID,
    kindID: DesignEntityKindID,
    fields: [DesignFieldID: DesignValue] = [:],
    relations: [DesignRelationKindID: Set<DesignEntityID>] = [:],
    spatialEntries: [DesignSpatialEntry] = []
  ) {
    self.key = key
    self.facetID = facetID
    self.kindID = kindID
    self.fields = fields
    self.relations = relations
    self.spatialEntries = spatialEntries
  }
}
