import CircuiteFoundation

public struct DesignFacetChange: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let facetID: DesignFacetID
  public let kind: DesignFacetChangeKind
  public let before: DesignFacetRoot?
  public let after: DesignFacetRoot?

  public init(
    facetID: DesignFacetID,
    kind: DesignFacetChangeKind,
    before: DesignFacetRoot?,
    after: DesignFacetRoot?
  ) throws(DesignDatabaseError) {
    guard before?.facetID == facetID || before == nil,
          after?.facetID == facetID || after == nil else {
      throw .invalidRevisionDiff(
        reason: "A facet change root must match its facet identity."
      )
    }
    let isValid: Bool
    switch kind {
    case .added:
      isValid = before == nil && after != nil
    case .removed:
      isValid = before != nil && after == nil
    case .modified:
      isValid = before != nil && after != nil && before != after
    }
    guard isValid else {
      throw .invalidRevisionDiff(
        reason: "A facet change does not match its declared change kind."
      )
    }
    self.facetID = facetID
    self.kind = kind
    self.before = before
    self.after = after
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.facetID.rawValue < rhs.facetID.rawValue
  }
}
