package struct DesignProjectionDecodedPageCacheMetrics: Sendable, Hashable {
  package let lookupCount: UInt64
  package let hitCount: UInt64
  package let missCount: UInt64
  package let databaseReadCount: UInt64
  package let decodeAttemptCount: UInt64
  package let payloadMaterializationByteCount: UInt64
  package let avoidedDatabaseReadCount: UInt64
  package let avoidedDecodeCount: UInt64
  package let avoidedPayloadMaterializationByteCount: UInt64
  package let insertionCount: UInt64
  package let redundantLoadCount: UInt64
  package let evictionCount: UInt64
  package let residentEntryCount: UInt64
  package let accountedResidentByteCount: UInt64
  package let activeLeaseCount: UInt64

  package static let zero = DesignProjectionDecodedPageCacheMetrics(
    lookupCount: 0,
    hitCount: 0,
    missCount: 0,
    databaseReadCount: 0,
    decodeAttemptCount: 0,
    payloadMaterializationByteCount: 0,
    avoidedDatabaseReadCount: 0,
    avoidedDecodeCount: 0,
    avoidedPayloadMaterializationByteCount: 0,
    insertionCount: 0,
    redundantLoadCount: 0,
    evictionCount: 0,
    residentEntryCount: 0,
    accountedResidentByteCount: 0,
    activeLeaseCount: 0
  )

  package func adding(
    _ other: DesignProjectionDecodedPageCacheMetrics
  ) -> DesignProjectionDecodedPageCacheMetrics {
    DesignProjectionDecodedPageCacheMetrics(
      lookupCount: Self.saturatingAdd(lookupCount, other.lookupCount),
      hitCount: Self.saturatingAdd(hitCount, other.hitCount),
      missCount: Self.saturatingAdd(missCount, other.missCount),
      databaseReadCount: Self.saturatingAdd(
        databaseReadCount,
        other.databaseReadCount
      ),
      decodeAttemptCount: Self.saturatingAdd(
        decodeAttemptCount,
        other.decodeAttemptCount
      ),
      payloadMaterializationByteCount: Self.saturatingAdd(
        payloadMaterializationByteCount,
        other.payloadMaterializationByteCount
      ),
      avoidedDatabaseReadCount: Self.saturatingAdd(
        avoidedDatabaseReadCount,
        other.avoidedDatabaseReadCount
      ),
      avoidedDecodeCount: Self.saturatingAdd(
        avoidedDecodeCount,
        other.avoidedDecodeCount
      ),
      avoidedPayloadMaterializationByteCount: Self.saturatingAdd(
        avoidedPayloadMaterializationByteCount,
        other.avoidedPayloadMaterializationByteCount
      ),
      insertionCount: Self.saturatingAdd(
        insertionCount,
        other.insertionCount
      ),
      redundantLoadCount: Self.saturatingAdd(
        redundantLoadCount,
        other.redundantLoadCount
      ),
      evictionCount: Self.saturatingAdd(
        evictionCount,
        other.evictionCount
      ),
      residentEntryCount: Self.saturatingAdd(
        residentEntryCount,
        other.residentEntryCount
      ),
      accountedResidentByteCount: Self.saturatingAdd(
        accountedResidentByteCount,
        other.accountedResidentByteCount
      ),
      activeLeaseCount: Self.saturatingAdd(
        activeLeaseCount,
        other.activeLeaseCount
      )
    )
  }

  private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? UInt64.max : result
  }
}
