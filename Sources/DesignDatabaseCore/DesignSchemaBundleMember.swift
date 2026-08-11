import CircuiteFoundation

public struct DesignSchemaBundleMember: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let schemaID: DesignSchemaID
  public let version: SchemaVersion
  public let canonicalDigest: ContentDigest

  public init(
    schemaID: DesignSchemaID,
    version: SchemaVersion,
    canonicalDigest: ContentDigest
  ) {
    self.schemaID = schemaID
    self.version = version
    self.canonicalDigest = canonicalDigest
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.schemaID != rhs.schemaID { return lhs.schemaID < rhs.schemaID }
    if lhs.version != rhs.version { return lhs.version < rhs.version }
    if lhs.canonicalDigest.algorithm.rawValue != rhs.canonicalDigest.algorithm.rawValue {
      return lhs.canonicalDigest.algorithm.rawValue < rhs.canonicalDigest.algorithm.rawValue
    }
    return lhs.canonicalDigest.hexadecimalValue < rhs.canonicalDigest.hexadecimalValue
  }
}
