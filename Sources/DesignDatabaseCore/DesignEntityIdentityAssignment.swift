import CircuiteFoundation

public struct DesignEntityIdentityAssignment:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable
{
  public let provisionalID: DesignProvisionalEntityID
  public let permanentID: DesignEntityID

  public init(
    provisionalID: DesignProvisionalEntityID,
    permanentID: DesignEntityID
  ) {
    self.provisionalID = provisionalID
    self.permanentID = permanentID
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.provisionalID < rhs.provisionalID
  }
}
