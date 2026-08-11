public enum DesignDatabaseRuntimePreparedMutationError: Error, Sendable, Hashable {
  case invalidImmutableWriteIndex(index: UInt64, writeCount: UInt64)
  case invalidImmutableWriteIdentity(reason: String)
}
