public enum DesignDatabaseServiceQueryPageCodecError:
  Error,
  Sendable,
  Equatable
{
  case invalidBudget(kind: String)
  case invalidMagic
  case unsupportedVersion(UInt16)
  case unsupportedFlags(UInt16)
  case truncated
  case trailingBytes(UInt64)
  case integerOverflow
  case budgetExceeded(kind: String, limit: UInt64, requested: UInt64)
  case invalidMetadata(reason: String)
  case invalidPage(reason: String)
}
