import CircuiteFoundation

struct DesignSpatialIndexRecord: Sendable, Hashable {
  let entityID: DesignEntityID
  let layer: DesignIndexKey?
  let bounds: DesignIntegerBounds
}
