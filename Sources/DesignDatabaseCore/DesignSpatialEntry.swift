import CircuiteFoundation

public struct DesignSpatialEntry: Sendable, Hashable, DesignDatabaseSerializable {
  public let container: DesignEntityID
  public let layer: DesignIndexKey?
  public let bounds: DesignIntegerBounds

  public init(
    container: DesignEntityID,
    layer: DesignIndexKey? = nil,
    bounds: DesignIntegerBounds
  ) {
    self.container = container
    self.layer = layer
    self.bounds = bounds
  }
}
