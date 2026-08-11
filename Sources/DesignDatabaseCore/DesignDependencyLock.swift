public struct DesignDependencyLock: Sendable, Hashable, DesignDatabaseSerializable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let entries: [DesignDependencyLockEntry]

  public init(
    entries: [DesignDependencyLockEntry],
    schemaVersion: Int = Self.currentSchemaVersion
  ) throws(DesignDatabaseError) {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw .invalidDependencyLock(
        reason: "The dependency-lock schema version is unsupported."
      )
    }
    let ordered = entries.sorted()
    guard Set(ordered.map { $0.dependencyID }).count == ordered.count else {
      throw .invalidDependencyLock(
        reason: "A direct dependency identifier appears more than once."
      )
    }
    self.schemaVersion = schemaVersion
    self.entries = ordered
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        entries: container.decode(
          [DesignDependencyLockEntry].self,
          forKey: .entries
        ),
        schemaVersion: container.decode(Int.self, forKey: .schemaVersion)
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
}
