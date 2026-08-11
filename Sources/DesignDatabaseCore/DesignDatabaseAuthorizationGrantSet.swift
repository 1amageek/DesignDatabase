public struct DesignDatabaseAuthorizationGrantSet:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public let grants: [DesignDatabaseAuthorizationGrant]

  public init(_ grants: some Sequence<DesignDatabaseAuthorizationGrant>) {
    let ordered = Array(grants).sorted()
    var unique: [DesignDatabaseAuthorizationGrant] = []
    unique.reserveCapacity(ordered.count)
    for grant in ordered where unique.last != grant {
      unique.append(grant)
    }
    self.grants = unique
  }

  public func contains(_ grant: DesignDatabaseAuthorizationGrant) -> Bool {
    grants.binarySearch(for: grant)
  }

  public func isSubset(of other: Self) -> Bool {
    grants.allSatisfy(other.contains)
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    self.init(try container.decode([DesignDatabaseAuthorizationGrant].self))
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(grants)
  }
#endif
}

private extension Array where Element == DesignDatabaseAuthorizationGrant {
  func binarySearch(for value: Element) -> Bool {
    var lowerBound = startIndex
    var upperBound = endIndex

    while lowerBound < upperBound {
      let distance = self.distance(from: lowerBound, to: upperBound)
      let midpoint = index(lowerBound, offsetBy: distance / 2)
      if self[midpoint] == value {
        return true
      }
      if self[midpoint] < value {
        lowerBound = index(after: midpoint)
      } else {
        upperBound = midpoint
      }
    }
    return false
  }
}
