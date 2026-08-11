public struct DesignProjectionChange: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let family: DesignProjectionFamily
  public let before: DesignProjectionEntry?
  public let after: DesignProjectionEntry?

  public init(
    family: DesignProjectionFamily,
    before: DesignProjectionEntry?,
    after: DesignProjectionEntry?
  ) throws(DesignDatabaseError) {
    guard before != nil || after != nil else {
      throw .invalidMutationPlan(
        reason: "A projection change must contain a before or after entry."
      )
    }
    if let before, let after, before.key != after.key {
      throw .invalidMutationPlan(
        reason: "A projection change cannot move between canonical keys."
      )
    }
    guard before != after else {
      throw .invalidMutationPlan(
        reason: "A projection change must alter its canonical entry."
      )
    }
    self.family = family
    self.before = before
    self.after = after
  }

  public var key: DesignCanonicalKey {
    before?.key ?? after!.key
  }

  public static func < (
    lhs: DesignProjectionChange,
    rhs: DesignProjectionChange
  ) -> Bool {
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    return lhs.key < rhs.key
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        family: container.decode(
          DesignProjectionFamily.self,
          forKey: .family
        ),
        before: container.decodeIfPresent(
          DesignProjectionEntry.self,
          forKey: .before
        ),
        after: container.decodeIfPresent(
          DesignProjectionEntry.self,
          forKey: .after
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  private enum CodingKeys: String, CodingKey {
    case family
    case before
    case after
  }
#endif
}
