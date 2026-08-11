import CircuiteFoundation

public enum DesignDatabaseRuntimeMutationAdapterError:
  Error,
  Sendable,
  Hashable
{
  case invalidPayload(reason: String)
  case validationFailed(
    diagnostics: [DesignDiagnostic],
    diagnosticsDigest: ContentDigest
  )
  case budgetExceeded(limit: UInt64, requested: UInt64)
}
