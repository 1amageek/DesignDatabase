import CircuiteFoundation

public struct DesignSemanticDependencyGraphIdentity:
  Sendable,
  Hashable,
  DesignDatabaseSerializable
{
  public enum Source: Sendable, Hashable, DesignDatabaseSerializable {
    case root
    case databaseRevision(DesignRevisionReference)
  }

  public struct Node: Sendable, Hashable, DesignDatabaseSerializable {
    public let target: DesignDependencyTarget
    public let stateDigest: ContentDigest?
    public let designSchemaBundleDigest: ContentDigest?

    public init(
      target: DesignDependencyTarget,
      stateDigest: ContentDigest? = nil,
      designSchemaBundleDigest: ContentDigest? = nil
    ) throws(DesignDatabaseError) {
      switch target {
      case .databaseRevision:
        guard stateDigest?.algorithm == .sha256,
              designSchemaBundleDigest?.algorithm == .sha256 else {
          throw .invalidDependencyLock(
            reason: "A resolved database dependency node requires SHA-256 state and schema identities."
          )
        }
      case .artifactContent:
        guard stateDigest == nil, designSchemaBundleDigest == nil else {
          throw .invalidDependencyLock(
            reason: "A resolved artifact dependency node cannot carry database state identities."
          )
        }
      }
      self.target = target
      self.stateDigest = stateDigest
      self.designSchemaBundleDigest = designSchemaBundleDigest
    }
  }

  public struct Edge: Sendable, Hashable, DesignDatabaseSerializable {
    public let source: Source
    public let dependency: DesignDependencyLockEntry

    public init(
      source: Source,
      dependency: DesignDependencyLockEntry
    ) {
      self.source = source
      self.dependency = dependency
    }
  }

  public let nodes: [Node]
  public let edges: [Edge]

  public init(
    nodes: [Node],
    edges: [Edge]
  ) throws(DesignDatabaseError) {
    var nodesByTarget: [DesignDependencyTarget: Node] = [:]
    for node in nodes {
      if let existing = nodesByTarget[node.target] {
        guard existing == node else {
          throw .invalidDependencyLock(
            reason: "A semantic dependency graph contains conflicting identities for one exact target node."
          )
        }
      } else {
        nodesByTarget[node.target] = node
      }
    }
    let orderedNodes = nodesByTarget.values.sorted(by: Self.nodeOrder)
    let nodeTargets = Set(orderedNodes.map { $0.target })
    var edgesByKey: [String: Edge] = [:]
    for edge in edges {
      guard nodeTargets.contains(edge.dependency.target) else {
        throw .invalidDependencyLock(
          reason: "A semantic dependency edge targets an absent exact node."
        )
      }
      if case .databaseRevision(let sourceRevision) = edge.source {
        guard nodeTargets.contains(.databaseRevision(sourceRevision)) else {
          throw .invalidDependencyLock(
            reason: "A semantic dependency edge starts from an absent database node."
          )
        }
      }
      let key = Self.sourceIdentity(edge.source)
        + "\u{0}" + edge.dependency.dependencyID.rawValue
      if let existing = edgesByKey[key] {
        guard existing == edge else {
          throw .invalidDependencyLock(
            reason: "A semantic dependency source repeats a direct dependency identifier with conflicting content."
          )
        }
      } else {
        edgesByKey[key] = edge
      }
    }
    self.nodes = orderedNodes
    self.edges = edgesByKey.values.sorted(by: Self.edgeOrder)
  }

  private static func nodeOrder(_ lhs: Node, _ rhs: Node) -> Bool {
    targetIdentity(lhs.target) < targetIdentity(rhs.target)
  }

  private static func edgeOrder(_ lhs: Edge, _ rhs: Edge) -> Bool {
    let left = (
      sourceIdentity(lhs.source),
      lhs.dependency.dependencyID.rawValue
    )
    let right = (
      sourceIdentity(rhs.source),
      rhs.dependency.dependencyID.rawValue
    )
    return left < right
  }

  private static func sourceIdentity(_ source: Source) -> String {
    switch source {
    case .root:
      return "root"
    case .databaseRevision(let revision):
      return "database:\(revision.databaseID.description):revision:\(revision.revisionID.description)"
    }
  }

  private static func targetIdentity(_ target: DesignDependencyTarget) -> String {
    switch target {
    case .databaseRevision(let revision):
      return "database:\(revision.databaseID.description):revision:\(revision.revisionID.description)"
    case .artifactContent(let artifactID):
      return "artifact:\(artifactID.description)"
    }
  }
}
