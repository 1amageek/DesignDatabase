import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseServiceSnapshotDescriptor:
  Sendable,
  Hashable,
  Codable
{
  public let snapshotID: DesignDatabaseServiceSnapshotID
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let designSchemaBundle: DesignSchemaBundle
  public let designSchemaBundleDigest: ContentDigest
  public let directDependencyLock: DesignDependencyLock
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let facetRoots: [DesignFacetRoot]
  public let directChangeRootDigest: ContentDigest
  public let projectionSemantics: [DesignProjectionSemanticDescriptor]
  public let materializationBindings: DesignProjectionMaterializationBindingSet

  public init(
    snapshotID: DesignDatabaseServiceSnapshotID,
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference],
    stateDigest: ContentDigest,
    designSchemaBundle: DesignSchemaBundle,
    designSchemaBundleDigest: ContentDigest,
    directDependencyLock: DesignDependencyLock,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    directChangeRootDigest: ContentDigest,
    projectionSemantics: [DesignProjectionSemanticDescriptor],
    materializationBindings: DesignProjectionMaterializationBindingSet
  ) throws(DesignDatabaseError) {
    let state = try DesignRevisionStateDescriptor(
      revision: revision,
      parents: parents,
      stateDigest: stateDigest,
      designSchemaBundleDigest: designSchemaBundleDigest,
      dependencyRootDigest: dependencyRootDigest,
      semanticDependencyGraphDigest: semanticDependencyGraphDigest,
      facetRoots: facetRoots,
      directChangeRootDigest: directChangeRootDigest
    )
    let orderedProjectionSemantics = projectionSemantics.sorted()
    guard designSchemaBundle.rootDigest == state.designSchemaBundleDigest else {
      throw .invalidSchemaBundle(
        reason: "A service snapshot schema bundle does not match its revision schema root."
      )
    }
    for index in orderedProjectionSemantics.indices.dropFirst() where
      orderedProjectionSemantics[index - 1].family
        == orderedProjectionSemantics[index].family {
      throw .invalidQuery(
        "A service snapshot descriptor contains duplicate projection semantics."
      )
    }
    guard orderedProjectionSemantics.map(\.family)
      == materializationBindings.bindings.map(\.family) else {
      throw .invalidQuery(
        "A service snapshot descriptor does not bind every projection semantic family exactly once."
      )
    }
    self.snapshotID = snapshotID
    self.revision = state.revision
    self.parents = state.parents
    self.stateDigest = state.stateDigest
    self.designSchemaBundle = designSchemaBundle
    self.designSchemaBundleDigest = state.designSchemaBundleDigest
    self.directDependencyLock = directDependencyLock
    self.dependencyRootDigest = state.dependencyRootDigest
    self.semanticDependencyGraphDigest = state.semanticDependencyGraphDigest
    self.facetRoots = state.facetRoots
    self.directChangeRootDigest = state.directChangeRootDigest
    self.projectionSemantics = orderedProjectionSemantics
    self.materializationBindings = materializationBindings
  }

  private enum CodingKeys: String, CodingKey {
    case snapshotID
    case revision
    case parents
    case stateDigest
    case designSchemaBundle
    case designSchemaBundleDigest
    case directDependencyLock
    case dependencyRootDigest
    case semanticDependencyGraphDigest
    case facetRoots
    case directChangeRootDigest
    case projectionSemantics
    case materializationBindings
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        snapshotID: container.decode(
          DesignDatabaseServiceSnapshotID.self,
          forKey: .snapshotID
        ),
        revision: container.decode(
          DesignRevisionReference.self,
          forKey: .revision
        ),
        parents: container.decode(
          [DesignRevisionReference].self,
          forKey: .parents
        ),
        stateDigest: container.decode(
          ContentDigest.self,
          forKey: .stateDigest
        ),
        designSchemaBundle: container.decode(
          DesignSchemaBundle.self,
          forKey: .designSchemaBundle
        ),
        designSchemaBundleDigest: container.decode(
          ContentDigest.self,
          forKey: .designSchemaBundleDigest
        ),
        directDependencyLock: container.decode(
          DesignDependencyLock.self,
          forKey: .directDependencyLock
        ),
        dependencyRootDigest: container.decode(
          ContentDigest.self,
          forKey: .dependencyRootDigest
        ),
        semanticDependencyGraphDigest: container.decode(
          ContentDigest.self,
          forKey: .semanticDependencyGraphDigest
        ),
        facetRoots: container.decode(
          [DesignFacetRoot].self,
          forKey: .facetRoots
        ),
        directChangeRootDigest: container.decode(
          ContentDigest.self,
          forKey: .directChangeRootDigest
        ),
        projectionSemantics: container.decode(
          [DesignProjectionSemanticDescriptor].self,
          forKey: .projectionSemantics
        ),
        materializationBindings: container.decode(
          DesignProjectionMaterializationBindingSet.self,
          forKey: .materializationBindings
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
}
