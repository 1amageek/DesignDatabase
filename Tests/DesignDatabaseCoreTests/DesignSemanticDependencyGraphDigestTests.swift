import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore
import Foundation
import Testing

@Suite("Semantic dependency graph digest")
struct DesignSemanticDependencyGraphDigestTests {
  @Test("Canonical digest is order-independent and constraint-sensitive")
  func canonicalIdentity() throws {
    let databaseRevision = DesignRevisionReference(
      databaseID: try DesignDatabaseID(high: 301, low: 1),
      revisionID: DesignRevisionID(high: 301, low: 2)
    )
    let artifactID = try ArtifactID(
      digest: digest("artifact"),
      byteCount: 8
    )
    let schema = DesignSchemaBundleMember(
      schemaID: try DesignSchemaID(rawValue: "lsi.graph.fixture"),
      version: .v1,
      canonicalDigest: try digest("schema")
    )
    let rootEntry = try DesignDependencyLockEntry(
      dependencyID: DesignDependencyID(rawValue: "database"),
      semanticRole: "library",
      target: .databaseRevision(databaseRevision),
      requiredSchemas: [schema],
      interfaceDigest: try digest("database-interface"),
      retentionContractIdentity: "not-required"
    )
    let artifactEntry = try DesignDependencyLockEntry(
      dependencyID: DesignDependencyID(rawValue: "model"),
      semanticRole: "model",
      target: .artifactContent(artifactID),
      interfaceDigest: try digest("artifact-interface"),
      retentionContractIdentity: "not-required"
    )
    let databaseNode = try DesignSemanticDependencyGraphIdentity.Node(
      target: .databaseRevision(databaseRevision),
      stateDigest: try digest("state"),
      designSchemaBundleDigest: try digest("schema-bundle")
    )
    let artifactNode = try DesignSemanticDependencyGraphIdentity.Node(
      target: .artifactContent(artifactID)
    )
    let rootEdge = DesignSemanticDependencyGraphIdentity.Edge(
      source: .root,
      dependency: rootEntry
    )
    let artifactEdge = DesignSemanticDependencyGraphIdentity.Edge(
      source: .databaseRevision(databaseRevision),
      dependency: artifactEntry
    )
    let first = try DesignSemanticDependencyGraphIdentity(
      nodes: [databaseNode, artifactNode],
      edges: [rootEdge, artifactEdge]
    )
    let reordered = try DesignSemanticDependencyGraphIdentity(
      nodes: [artifactNode, databaseNode, databaseNode],
      edges: [artifactEdge, rootEdge, rootEdge]
    )
    let firstDigest = try DesignSemanticDependencyGraphDigest.root(
      first,
      using: SHA256ContentDigester()
    )
    let reorderedDigest = try DesignSemanticDependencyGraphDigest.root(
      reordered,
      using: SHA256ContentDigester()
    )
    #expect(firstDigest == reorderedDigest)

    let changedRootEntry = try DesignDependencyLockEntry(
      dependencyID: rootEntry.dependencyID,
      semanticRole: rootEntry.semanticRole,
      target: rootEntry.target,
      requiredSchemas: rootEntry.requiredSchemas,
      interfaceDigest: try digest("changed-interface"),
      retentionContractIdentity: rootEntry.retentionContractIdentity
    )
    let changed = try DesignSemanticDependencyGraphIdentity(
      nodes: first.nodes,
      edges: [
        DesignSemanticDependencyGraphIdentity.Edge(
          source: .root,
          dependency: changedRootEntry
        ),
        artifactEdge,
      ]
    )
    let changedDigest = try DesignSemanticDependencyGraphDigest.root(
      changed,
      using: SHA256ContentDigester()
    )
    #expect(firstDigest != changedDigest)
  }

  @Test("Empty semantic identity has one location-independent digest")
  func emptyIdentity() throws {
    let first = try DesignSemanticDependencyGraphDigest.root(
      DesignSemanticDependencyGraphIdentity(nodes: [], edges: []),
      using: SHA256ContentDigester()
    )
    let second = try DesignSemanticDependencyGraphDigest.root(
      DesignSemanticDependencyGraphIdentity(nodes: [], edges: []),
      using: SHA256ContentDigester()
    )
    #expect(first == second)
  }

  private func digest(_ value: String) throws -> ContentDigest {
    try SHA256ContentDigester().digest(data: Data(value.utf8))
  }
}
