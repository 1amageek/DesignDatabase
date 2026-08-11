import CircuiteFoundation

public struct DesignRelationOccurrenceIdentityAssignment:
  Sendable,
  Hashable,
  DesignDatabaseSerializable,
  Comparable
{
  public let provisionalID: DesignProvisionalRelationOccurrenceID
  public let permanentID: DesignRelationOccurrenceID

  public init(
    provisionalID: DesignProvisionalRelationOccurrenceID,
    permanentID: DesignRelationOccurrenceID
  ) {
    self.provisionalID = provisionalID
    self.permanentID = permanentID
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.provisionalID < rhs.provisionalID
  }
}
