public struct DesignProjectionSemanticVersion: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let major: UInt16
  public let minor: UInt16

  public init(major: UInt16, minor: UInt16) {
    self.major = major
    self.minor = minor
  }

  public static func < (
    lhs: DesignProjectionSemanticVersion,
    rhs: DesignProjectionSemanticVersion
  ) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    return lhs.minor < rhs.minor
  }
}
