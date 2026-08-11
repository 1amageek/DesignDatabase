import Synchronization

package final class DesignProjectionDecodedPageCache: Sendable {
  private final class Shard: Sendable {
    private struct Entry {
      let page: DesignProjectionDecodedPage
      var activeLeaseCount: UInt64
      var lastAccessOrdinal: UInt64
    }

    private struct State {
      var entries: [DesignProjectionDecodedPageKey: Entry] = [:]
      var nextAccessOrdinal: UInt64 = 0
      var lookupCount: UInt64 = 0
      var hitCount: UInt64 = 0
      var missCount: UInt64 = 0
      var databaseReadCount: UInt64 = 0
      var decodeAttemptCount: UInt64 = 0
      var payloadMaterializationByteCount: UInt64 = 0
      var avoidedDatabaseReadCount: UInt64 = 0
      var avoidedDecodeCount: UInt64 = 0
      var avoidedPayloadMaterializationByteCount: UInt64 = 0
      var insertionCount: UInt64 = 0
      var redundantLoadCount: UInt64 = 0
      var evictionCount: UInt64 = 0
      var accountedResidentByteCount: UInt64 = 0
      var activeLeaseCount: UInt64 = 0
      var isClosed = false
    }

    private let maximumEntryCount: Int
    private let maximumAccountedResidentByteCount: UInt64
    private let state = Mutex(State())

    init(
      maximumEntryCount: Int,
      maximumAccountedResidentByteCount: UInt64
    ) {
      self.maximumEntryCount = maximumEntryCount
      self.maximumAccountedResidentByteCount = maximumAccountedResidentByteCount
    }

    func borrow(
      _ key: DesignProjectionDecodedPageKey
    ) -> Result<DesignProjectionDecodedPage?, DesignDatabaseRuntimeError> {
      state.withLock { state in
        state.lookupCount = Self.saturatingIncrement(state.lookupCount)
        guard !state.isClosed, var entry = state.entries[key] else {
          state.missCount = Self.saturatingIncrement(state.missCount)
          return .success(nil)
        }
        let (leaseCount, leaseOverflow) = entry.activeLeaseCount
          .addingReportingOverflow(1)
        let (totalLeaseCount, totalLeaseOverflow) = state.activeLeaseCount
          .addingReportingOverflow(1)
        guard !leaseOverflow, !totalLeaseOverflow else {
          return .failure(
            DesignDatabaseRuntimeError.generationExhausted(
              kind: "decoded projection page lease"
            )
          )
        }
        entry.activeLeaseCount = leaseCount
        entry.lastAccessOrdinal = Self.nextAccessOrdinal(in: &state)
        state.entries[key] = entry
        state.activeLeaseCount = totalLeaseCount
        state.hitCount = Self.saturatingIncrement(state.hitCount)
        state.avoidedDatabaseReadCount = Self.saturatingIncrement(
          state.avoidedDatabaseReadCount
        )
        state.avoidedDecodeCount = Self.saturatingIncrement(
          state.avoidedDecodeCount
        )
        state.avoidedPayloadMaterializationByteCount = Self.saturatingAdd(
          state.avoidedPayloadMaterializationByteCount,
          entry.page.encodedByteCount
        )
        return .success(entry.page)
      }
    }

    func recordDatabaseRead() {
      state.withLock { state in
        state.databaseReadCount = Self.saturatingIncrement(
          state.databaseReadCount
        )
      }
    }

    func recordDecodeAttempt(encodedByteCount: UInt64) {
      state.withLock { state in
        state.decodeAttemptCount = Self.saturatingIncrement(
          state.decodeAttemptCount
        )
        state.payloadMaterializationByteCount = Self.saturatingAdd(
          state.payloadMaterializationByteCount,
          encodedByteCount
        )
      }
    }

    func insertAndBorrow(
      _ page: DesignProjectionDecodedPage,
      for key: DesignProjectionDecodedPageKey
    ) -> Result<
      (DesignProjectionDecodedPage, Bool),
      DesignDatabaseRuntimeError
    > {
      state.withLock { state in
        guard !state.isClosed else { return .success((page, false)) }
        if var existing = state.entries[key] {
          let (entryLeaseCount, entryOverflow) = existing.activeLeaseCount
            .addingReportingOverflow(1)
          let (totalLeaseCount, totalOverflow) = state.activeLeaseCount
            .addingReportingOverflow(1)
          guard !entryOverflow, !totalOverflow else {
            return .failure(
              DesignDatabaseRuntimeError.generationExhausted(
                kind: "decoded projection page lease"
              )
            )
          }
          existing.activeLeaseCount = entryLeaseCount
          existing.lastAccessOrdinal = Self.nextAccessOrdinal(in: &state)
          state.entries[key] = existing
          state.activeLeaseCount = totalLeaseCount
          state.redundantLoadCount = Self.saturatingIncrement(
            state.redundantLoadCount
          )
          return .success((existing.page, true))
        }

        guard page.accountedResidentByteCount
                <= maximumAccountedResidentByteCount else {
          return .success((page, false))
        }
        evictEntriesIfNeeded(
          for: page.accountedResidentByteCount,
          state: &state
        )
        let requestedEntryCount = state.entries.count + 1
        let requestedByteCount = state.accountedResidentByteCount
          + page.accountedResidentByteCount
        guard requestedEntryCount <= maximumEntryCount,
              requestedByteCount <= maximumAccountedResidentByteCount else {
          return .success((page, false))
        }
        let (totalLeaseCount, totalOverflow) = state.activeLeaseCount
          .addingReportingOverflow(1)
        guard !totalOverflow else {
          return .failure(
            DesignDatabaseRuntimeError.generationExhausted(
              kind: "decoded projection page lease"
            )
          )
        }
        let accessOrdinal = Self.nextAccessOrdinal(in: &state)
        state.entries[key] = Entry(
          page: page,
          activeLeaseCount: 1,
          lastAccessOrdinal: accessOrdinal
        )
        state.activeLeaseCount = totalLeaseCount
        state.accountedResidentByteCount = requestedByteCount
        state.insertionCount = Self.saturatingIncrement(state.insertionCount)
        return .success((page, true))
      }
    }

    func metrics() -> DesignProjectionDecodedPageCacheMetrics {
      state.withLock { state in
        DesignProjectionDecodedPageCacheMetrics(
          lookupCount: state.lookupCount,
          hitCount: state.hitCount,
          missCount: state.missCount,
          databaseReadCount: state.databaseReadCount,
          decodeAttemptCount: state.decodeAttemptCount,
          payloadMaterializationByteCount: state.payloadMaterializationByteCount,
          avoidedDatabaseReadCount: state.avoidedDatabaseReadCount,
          avoidedDecodeCount: state.avoidedDecodeCount,
          avoidedPayloadMaterializationByteCount: state.avoidedPayloadMaterializationByteCount,
          insertionCount: state.insertionCount,
          redundantLoadCount: state.redundantLoadCount,
          evictionCount: state.evictionCount,
          residentEntryCount: UInt64(state.entries.count),
          accountedResidentByteCount: state.accountedResidentByteCount,
          activeLeaseCount: state.activeLeaseCount
        )
      }
    }

    func close() {
      state.withLock { state in
        guard !state.isClosed else { return }
        state.isClosed = true
        state.entries.removeAll(keepingCapacity: false)
        state.accountedResidentByteCount = 0
      }
    }

    func release(_ key: DesignProjectionDecodedPageKey) {
      state.withLock { state in
        guard state.activeLeaseCount > 0 else { return }
        state.activeLeaseCount -= 1
        guard var entry = state.entries[key],
              entry.activeLeaseCount > 0 else {
          return
        }
        entry.activeLeaseCount -= 1
        state.entries[key] = entry
      }
    }

    private func evictEntriesIfNeeded(
      for requestedByteCount: UInt64,
      state: inout State
    ) {
      while state.entries.count >= maximumEntryCount
        || state.accountedResidentByteCount
          > maximumAccountedResidentByteCount - requestedByteCount {
        var candidate: (DesignProjectionDecodedPageKey, Entry)?
        for (key, entry) in state.entries where entry.activeLeaseCount == 0 {
          guard let current = candidate else {
            candidate = (key, entry)
            continue
          }
          if entry.lastAccessOrdinal < current.1.lastAccessOrdinal
            || (entry.lastAccessOrdinal == current.1.lastAccessOrdinal
              && key.canonicalSortKey < current.0.canonicalSortKey) {
            candidate = (key, entry)
          }
        }
        guard let candidate else { return }
        state.entries.removeValue(forKey: candidate.0)
        state.accountedResidentByteCount -= candidate.1.page
          .accountedResidentByteCount
        state.evictionCount = Self.saturatingIncrement(state.evictionCount)
      }
    }

    private static func nextAccessOrdinal(in state: inout State) -> UInt64 {
      if state.nextAccessOrdinal == UInt64.max {
        let ordered = state.entries.sorted {
          if $0.value.lastAccessOrdinal != $1.value.lastAccessOrdinal {
            return $0.value.lastAccessOrdinal < $1.value.lastAccessOrdinal
          }
          return $0.key.canonicalSortKey < $1.key.canonicalSortKey
        }
        for (index, pair) in ordered.enumerated() {
          var entry = pair.value
          entry.lastAccessOrdinal = UInt64(index)
          state.entries[pair.key] = entry
        }
        state.nextAccessOrdinal = UInt64(ordered.count)
      }
      state.nextAccessOrdinal += 1
      return state.nextAccessOrdinal
    }

    private static func saturatingIncrement(_ value: UInt64) -> UInt64 {
      value == UInt64.max ? UInt64.max : value + 1
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
      let (result, overflow) = lhs.addingReportingOverflow(rhs)
      return overflow ? UInt64.max : result
    }
  }

  private let shards: [Shard]

  package init(
    policy: DesignProjectionDecodedPageCachePolicy = .checkedDefault
  ) {
    let baseEntryCount = policy.maximumEntryCount / policy.shardCount
    let remainingEntryCount = policy.maximumEntryCount % policy.shardCount
    let shardCount = UInt64(policy.shardCount)
    let baseByteCount = policy.maximumAccountedResidentByteCount / shardCount
    let remainingByteCount = policy.maximumAccountedResidentByteCount
      % shardCount
    shards = (0..<policy.shardCount).map { index in
      Shard(
        maximumEntryCount: baseEntryCount
          + (index < remainingEntryCount ? 1 : 0),
        maximumAccountedResidentByteCount: baseByteCount
          + (UInt64(index) < remainingByteCount ? 1 : 0)
      )
    }
  }

  package func borrow(
    _ key: DesignProjectionDecodedPageKey
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionDecodedPageLease? {
    let outcome = shard(for: key).borrow(key)
    let page: DesignProjectionDecodedPage?
    switch outcome {
    case .success(let value):
      page = value
    case .failure(let error):
      throw error
    }
    guard let page else { return nil }
    return DesignProjectionDecodedPageLease(
      cache: self,
      key: key,
      page: page
    )
  }

  package func recordDatabaseRead(
    for key: DesignProjectionDecodedPageKey
  ) {
    shard(for: key).recordDatabaseRead()
  }

  package func recordDecodeAttempt(
    encodedByteCount: UInt64,
    for key: DesignProjectionDecodedPageKey
  ) {
    shard(for: key).recordDecodeAttempt(encodedByteCount: encodedByteCount)
  }

  package func insertAndBorrow(
    _ page: DesignProjectionDecodedPage,
    for key: DesignProjectionDecodedPageKey
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionDecodedPageLease {
    guard page.family == key.family,
          page.codecVersion == key.physicalCodecVersion,
          page.physicalProfileDigest == key.physicalProfileDigest,
          page.digest == key.nodeDigest else {
      throw .persistedStateCorrupt(
        reason: "A decoded projection page does not match its cache identity."
      )
    }
    let outcome = shard(for: key).insertAndBorrow(page, for: key)
    let result: (DesignProjectionDecodedPage, Bool)
    switch outcome {
    case .success(let value):
      result = value
    case .failure(let error):
      throw error
    }
    return DesignProjectionDecodedPageLease(
      cache: result.1 ? self : nil,
      key: key,
      page: result.0
    )
  }

  package func metrics() -> DesignProjectionDecodedPageCacheMetrics {
    shards.reduce(.zero) { result, shard in
      result.adding(shard.metrics())
    }
  }

  package func close() {
    for shard in shards {
      shard.close()
    }
  }

  package func release(_ key: DesignProjectionDecodedPageKey) {
    shard(for: key).release(key)
  }

  private func shard(for key: DesignProjectionDecodedPageKey) -> Shard {
    shards[Int(key.stableShardHash % UInt64(shards.count))]
  }
}
