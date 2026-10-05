import CircuiteFoundation

/// Bounds one collection call; Runtime also enforces its atomic transaction ceilings.
public struct DesignRevisionCollectionBudget: Sendable, Hashable, DesignDatabaseSerializable {
  public let maximumRevisionCount: UInt64
  public let maximumReferenceCount: UInt64
  public let maximumRetentionCount: UInt64
  public let maximumBuildIntentCount: UInt64
  public let maximumManifestCount: UInt64
  public let maximumGraphEdgeCount: UInt64
  public let maximumPhysicalIdentityCount: UInt64
  public let maximumPhysicalClaimCount: UInt64
  public let scanPageSize: Int
  public let maximumGenerationRetryCount: UInt64
  public let maximumPhysicalDeletionCount: UInt64

  public init(maximumRevisionCount: UInt64 = 256,
              maximumReferenceCount: UInt64 = 4_096,
              maximumRetentionCount: UInt64 = 4_096,
              maximumBuildIntentCount: UInt64 = 4_096,
              maximumManifestCount: UInt64 = 65_536,
              maximumGraphEdgeCount: UInt64 = 262_144,
              maximumPhysicalIdentityCount: UInt64 = 1_048_576,
              maximumPhysicalClaimCount: UInt64 = 256,
              scanPageSize: Int = 128,
              maximumGenerationRetryCount: UInt64 = 3,
              maximumPhysicalDeletionCount: UInt64 = 16) throws(DesignDatabaseError) {
    guard maximumRevisionCount > 0, maximumReferenceCount > 0, maximumRetentionCount > 0, maximumBuildIntentCount > 0, maximumManifestCount > 0, maximumGraphEdgeCount > 0, maximumPhysicalIdentityCount > 0, maximumPhysicalClaimCount > 0, scanPageSize > 0, maximumGenerationRetryCount > 0, maximumPhysicalDeletionCount > 0 else {
      throw .resourceExhausted(limit: 0, requested: 1)
    }
    self.maximumRevisionCount = maximumRevisionCount
    self.maximumReferenceCount = maximumReferenceCount
    self.maximumRetentionCount = maximumRetentionCount
    self.maximumBuildIntentCount = maximumBuildIntentCount
    self.maximumManifestCount = maximumManifestCount
    self.maximumGraphEdgeCount = maximumGraphEdgeCount
    self.maximumPhysicalIdentityCount = maximumPhysicalIdentityCount
    self.maximumPhysicalClaimCount = maximumPhysicalClaimCount
    self.scanPageSize = scanPageSize
    self.maximumGenerationRetryCount = maximumGenerationRetryCount
    self.maximumPhysicalDeletionCount = maximumPhysicalDeletionCount
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: CodingKey { case maximumRevisionCount, maximumReferenceCount, maximumRetentionCount, maximumBuildIntentCount, maximumManifestCount, maximumGraphEdgeCount, maximumPhysicalIdentityCount, maximumPhysicalClaimCount, scanPageSize, maximumGenerationRetryCount, maximumPhysicalDeletionCount }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(maximumRevisionCount: values.decode(UInt64.self, forKey: .maximumRevisionCount),
                  maximumReferenceCount: values.decode(UInt64.self, forKey: .maximumReferenceCount),
                  maximumRetentionCount: values.decode(UInt64.self, forKey: .maximumRetentionCount),
                  maximumBuildIntentCount: values.decode(UInt64.self, forKey: .maximumBuildIntentCount),
                  maximumManifestCount: values.decode(UInt64.self, forKey: .maximumManifestCount),
                  maximumGraphEdgeCount: values.decode(UInt64.self, forKey: .maximumGraphEdgeCount),
                  maximumPhysicalIdentityCount: values.decode(UInt64.self, forKey: .maximumPhysicalIdentityCount),
                  maximumPhysicalClaimCount: values.decode(UInt64.self, forKey: .maximumPhysicalClaimCount),
                  scanPageSize: values.decode(Int.self, forKey: .scanPageSize),
                  maximumGenerationRetryCount: values.decode(UInt64.self, forKey: .maximumGenerationRetryCount),
                  maximumPhysicalDeletionCount: values.decode(UInt64.self, forKey: .maximumPhysicalDeletionCount))
  }
#endif
}
