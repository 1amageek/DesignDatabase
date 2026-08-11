package struct DesignProjectionDecodedPageCachePolicy: Sendable, Hashable {
  package static let checkedDefault = DesignProjectionDecodedPageCachePolicy(
    shardCount: 16,
    maximumEntryCount: 4_096,
    maximumAccountedResidentByteCount: 64 * 1_024 * 1_024,
    validated: ()
  )

  package let shardCount: Int
  package let maximumEntryCount: Int
  package let maximumAccountedResidentByteCount: UInt64

  package init(
    shardCount: Int = 16,
    maximumEntryCount: Int,
    maximumAccountedResidentByteCount: UInt64
  ) throws(DesignDatabaseRuntimeError) {
    guard shardCount > 0,
          maximumEntryCount >= shardCount,
          maximumAccountedResidentByteCount >= UInt64(shardCount) else {
      throw .frameworkConfigurationFailed(
        reason: "A decoded projection page cache requires positive per-shard entry and byte capacity."
      )
    }
    self.shardCount = shardCount
    self.maximumEntryCount = maximumEntryCount
    self.maximumAccountedResidentByteCount = maximumAccountedResidentByteCount
  }

  private init(
    shardCount: Int,
    maximumEntryCount: Int,
    maximumAccountedResidentByteCount: UInt64,
    validated: Void
  ) {
    self.shardCount = shardCount
    self.maximumEntryCount = maximumEntryCount
    self.maximumAccountedResidentByteCount = maximumAccountedResidentByteCount
  }
}
