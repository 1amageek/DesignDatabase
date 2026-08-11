import DesignDatabaseCore

package struct DesignDatabaseRuntimePreparedWriteDirectory: Sendable {
  package let totalWriteCount: UInt64

  private let mutations: [any DesignDatabaseRuntimePreparedMutation]
  private let exclusiveUpperBounds: [UInt64]

  package init(
    _ mutations: [any DesignDatabaseRuntimePreparedMutation]
  ) throws(DesignDatabaseRuntimeError) {
    var exclusiveUpperBounds: [UInt64] = []
    exclusiveUpperBounds.reserveCapacity(mutations.count)
    var totalWriteCount: UInt64 = 0
    for mutation in mutations {
      let (next, overflow) = totalWriteCount.addingReportingOverflow(
        mutation.writeCount
      )
      guard !overflow else {
        throw .commitTransactionFailed(
          reason: "The prepared immutable write count overflowed."
        )
      }
      totalWriteCount = next
      exclusiveUpperBounds.append(next)
    }
    self.mutations = mutations
    self.exclusiveUpperBounds = exclusiveUpperBounds
    self.totalWriteCount = totalWriteCount
  }

  package func resolve(
    _ globalIndex: UInt64
  ) throws(DesignDatabaseRuntimeError) -> (
    mutation: any DesignDatabaseRuntimePreparedMutation,
    localIndex: UInt64,
    identity: DesignDatabaseRuntimeImmutableWriteIdentity
  ) {
    guard globalIndex < totalWriteCount else {
      throw .persistedStateCorrupt(
        reason: "A staged immutable write index exceeded its prepared directory."
      )
    }
    var lowerBound = 0
    var upperBound = exclusiveUpperBounds.count
    while lowerBound < upperBound {
      let middle = lowerBound + (upperBound - lowerBound) / 2
      if globalIndex < exclusiveUpperBounds[middle] {
        upperBound = middle
      } else {
        lowerBound = middle + 1
      }
    }
    let previousUpperBound = lowerBound == 0
      ? 0
      : exclusiveUpperBounds[lowerBound - 1]
    let mutation = mutations[lowerBound]
    let localIndex = globalIndex - previousUpperBound
    do {
      return (
        mutation,
        localIndex,
        try mutation.immutableWriteIdentity(at: localIndex)
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A prepared mutation could not reproduce its physical write identity."
      )
    }
  }
}
