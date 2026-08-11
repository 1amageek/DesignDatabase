public enum DesignDatabaseAuthorizationGrant:
  String,
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  CaseIterable,
  Comparable
{
  case read
  case proposeCandidate
  case promoteReference
  case retain
  case inspectOwnOperationOutcome
  case administer

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
