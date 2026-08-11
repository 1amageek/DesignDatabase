import CircuiteFoundation

public struct DesignDependencyLockUpdate: Sendable, Hashable, DesignDatabaseSerializable {
  public let replacement: DesignDependencyLock
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest

  public init(
    replacement: DesignDependencyLock,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest
  ) throws(DesignDatabaseError) {
    guard dependencyRootDigest.algorithm == .sha256,
          semanticDependencyGraphDigest.algorithm == .sha256 else {
      throw .invalidDependencyLock(
        reason: "Dependency update identities must use SHA-256."
      )
    }
    self.replacement = replacement
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        replacement: container.decode(
          DesignDependencyLock.self,
          forKey: .replacement
        ),
        dependencyRootDigest: container.decode(
          ContentDigest.self,
          forKey: .dependencyRootDigest
        ),
        semanticDependencyGraphDigest: container.decode(
          ContentDigest.self,
          forKey: .semanticDependencyGraphDigest
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
}
