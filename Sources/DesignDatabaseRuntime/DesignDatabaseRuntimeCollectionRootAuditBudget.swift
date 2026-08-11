package struct DesignDatabaseRuntimeCollectionRootAuditBudget: Sendable {
  package let maximumReferenceCount: UInt64
  package let maximumRetentionCount: UInt64
  package let maximumBuildIntentCount: UInt64
  package let maximumManifestCount: UInt64
  package let maximumGraphEdgeCount: UInt64
  package let maximumPhysicalIdentityCount: UInt64
  package let maximumPhysicalClaimCount: UInt64
  package let scanPageSize: Int
  package let maximumGenerationRetryCount: UInt64

  package init(
    maximumReferenceCount: UInt64 = 4_096,
    maximumRetentionCount: UInt64 = 4_096,
    maximumBuildIntentCount: UInt64 = 4_096,
    maximumManifestCount: UInt64 = 65_536,
    maximumGraphEdgeCount: UInt64 = 262_144,
    maximumPhysicalIdentityCount: UInt64 = 1_048_576,
    maximumPhysicalClaimCount: UInt64 = 256,
    scanPageSize: Int = 128,
    maximumGenerationRetryCount: UInt64 = 3
  ) throws(DesignDatabaseRuntimeError) {
    guard maximumReferenceCount > 0,
          maximumRetentionCount > 0,
          maximumBuildIntentCount > 0,
          maximumManifestCount > 0,
          maximumGraphEdgeCount > 0,
          maximumPhysicalIdentityCount > 0,
          maximumPhysicalClaimCount > 0,
          scanPageSize > 0,
          maximumGenerationRetryCount > 0 else {
      throw .collectionRootAuditBudgetExceeded(
        kind: "configuration",
        limit: 0,
        requested: 1
      )
    }
    self.maximumReferenceCount = maximumReferenceCount
    self.maximumRetentionCount = maximumRetentionCount
    self.maximumBuildIntentCount = maximumBuildIntentCount
    self.maximumManifestCount = maximumManifestCount
    self.maximumGraphEdgeCount = maximumGraphEdgeCount
    self.maximumPhysicalIdentityCount = maximumPhysicalIdentityCount
    self.maximumPhysicalClaimCount = maximumPhysicalClaimCount
    self.scanPageSize = scanPageSize
    self.maximumGenerationRetryCount = maximumGenerationRetryCount
  }
}
