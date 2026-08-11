public struct DesignProjectionMaterializationBinding: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let family: DesignProjectionFamily
  public let materialization: DesignProjectionMaterializationReference

  public init(
    family: DesignProjectionFamily,
    materialization: DesignProjectionMaterializationReference
  ) {
    self.family = family
    self.materialization = materialization
  }

  public static func < (
    lhs: DesignProjectionMaterializationBinding,
    rhs: DesignProjectionMaterializationBinding
  ) -> Bool {
    lhs.family < rhs.family
  }
}
