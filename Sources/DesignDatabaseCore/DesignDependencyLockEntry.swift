import CircuiteFoundation

public struct DesignDependencyLockEntry: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let dependencyID: DesignDependencyID
  public let semanticRole: String
  public let target: DesignDependencyTarget
  public let requiredSchemas: [DesignSchemaBundleMember]
  public let requiredCapabilities: [DesignCapabilityRequirement]
  public let interfaceDigest: ContentDigest
  public let retentionContractIdentity: String

  public init(
    dependencyID: DesignDependencyID,
    semanticRole: String,
    target: DesignDependencyTarget,
    requiredSchemas: [DesignSchemaBundleMember] = [],
    requiredCapabilities: [DesignCapabilityRequirement] = [],
    interfaceDigest: ContentDigest,
    retentionContractIdentity: String
  ) throws(DesignDatabaseError) {
    try DesignDatabaseToken.validate(
      semanticRole,
      kind: "Design dependency semantic role"
    )
    try DesignDatabaseToken.validate(
      retentionContractIdentity,
      kind: "Design dependency retention contract identity"
    )
    guard interfaceDigest.algorithm == .sha256 else {
      throw .invalidDependencyLock(
        reason: "A dependency interface digest must use SHA-256."
      )
    }
    switch target {
    case .databaseRevision:
      break
    case .artifactContent(let artifactID):
      guard artifactID.digest.algorithm == .sha256 else {
        throw .invalidDependencyLock(
          reason: "A dependency artifact identity must use SHA-256."
        )
      }
    }

    let schemas = requiredSchemas.sorted()
    guard Set(schemas.map { $0.schemaID }).count == schemas.count,
          schemas.allSatisfy({ $0.canonicalDigest.algorithm == .sha256 }) else {
      throw .invalidDependencyLock(
        reason: "Required dependency schemas must be unique and content-addressed with SHA-256."
      )
    }
    let capabilities = requiredCapabilities.sorted(by: Self.capabilitySort)
    guard Set(capabilities.map { $0.capabilityID }).count == capabilities.count,
          capabilities.allSatisfy({ $0.necessity == .required }) else {
      throw .invalidDependencyLock(
        reason: "Dependency capability requirements must be unique and required."
      )
    }

    self.dependencyID = dependencyID
    self.semanticRole = semanticRole
    self.target = target
    self.requiredSchemas = schemas
    self.requiredCapabilities = capabilities
    self.interfaceDigest = interfaceDigest
    self.retentionContractIdentity = retentionContractIdentity
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        dependencyID: container.decode(
          DesignDependencyID.self,
          forKey: .dependencyID
        ),
        semanticRole: container.decode(String.self, forKey: .semanticRole),
        target: container.decode(DesignDependencyTarget.self, forKey: .target),
        requiredSchemas: container.decode(
          [DesignSchemaBundleMember].self,
          forKey: .requiredSchemas
        ),
        requiredCapabilities: container.decode(
          [DesignCapabilityRequirement].self,
          forKey: .requiredCapabilities
        ),
        interfaceDigest: container.decode(
          ContentDigest.self,
          forKey: .interfaceDigest
        ),
        retentionContractIdentity: container.decode(
          String.self,
          forKey: .retentionContractIdentity
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

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.dependencyID < rhs.dependencyID
  }

  private static func capabilitySort(
    _ lhs: DesignCapabilityRequirement,
    _ rhs: DesignCapabilityRequirement
  ) -> Bool {
    if lhs.capabilityID != rhs.capabilityID {
      return lhs.capabilityID < rhs.capabilityID
    }
    if lhs.versions.lowerBound != rhs.versions.lowerBound {
      return lhs.versions.lowerBound < rhs.versions.lowerBound
    }
    if lhs.versions.upperBound != rhs.versions.upperBound {
      return lhs.versions.upperBound < rhs.versions.upperBound
    }
    return lhs.necessity.rawValue < rhs.necessity.rawValue
  }
}
