public enum DesignQueryCompletion: String, Sendable, Hashable, DesignDatabaseSerializable {
  case sourceExhausted = "source-exhausted"
  case pageLimitReached = "page-limit-reached"
  case queryBudgetExhausted = "query-budget-exhausted"
}
