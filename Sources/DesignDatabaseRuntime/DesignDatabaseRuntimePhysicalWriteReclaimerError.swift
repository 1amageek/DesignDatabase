public enum DesignDatabaseRuntimePhysicalWriteReclaimerError:
  Error,
  Sendable,
  Equatable
{
  case identityBindingMismatch(reason: String)
  case persistedWriteNotFound(identity: String)
  case deleteFailed(reason: String)
}
