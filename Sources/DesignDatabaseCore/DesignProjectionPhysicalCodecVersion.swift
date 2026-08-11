public struct DesignProjectionPhysicalCodecVersion: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let major: UInt16
  public let minor: UInt16

  public init(major: UInt16, minor: UInt16) {
    self.major = major
    self.minor = minor
  }

  public static func < (
    lhs: DesignProjectionPhysicalCodecVersion,
    rhs: DesignProjectionPhysicalCodecVersion
  ) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    return lhs.minor < rhs.minor
  }
}
