import DesignDatabaseCore

extension DesignDatabaseRuntimeDigestEncoder {
  package mutating func append(
    projectionChanges: [DesignProjectionChange]
  ) throws(DesignDatabaseRuntimeError) {
    guard let count = UInt32(exactly: projectionChanges.count) else {
      throw .commitTransactionFailed(
        reason: "A projection change count is not representable."
      )
    }
    append(count)
    for change in projectionChanges {
      append(change.family.rawValue)
      append(change.key.bytes)
      append(change.before == nil ? UInt16(0) : UInt16(1))
      if let before = change.before {
        append(before.key.bytes)
        append(before.value)
      }
      append(change.after == nil ? UInt16(0) : UInt16(1))
      if let after = change.after {
        append(after.key.bytes)
        append(after.value)
      }
    }
  }
}
