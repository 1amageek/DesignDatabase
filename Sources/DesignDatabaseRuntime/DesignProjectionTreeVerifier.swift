import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionTreeVerifier: Sendable {
  package init() {}

  package func verify(
    _ materialization: DesignProjectionTreeMaterialization,
    profile: DesignProjectionPhysicalProfile,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) {
    let nodes = Dictionary(uniqueKeysWithValues: materialization.nodes.map {
      ($0.digest, $0)
    })
    guard nodes.count == materialization.nodes.count,
          materialization.totalNodeCount == UInt64(materialization.nodes.count),
          let root = nodes[materialization.reference.rootNodeDigest] else {
      throw .persistedStateCorrupt(
        reason: "A projection materialization has duplicate or missing nodes."
      )
    }
    var visited: Set<ContentDigest> = []
    let entries = try verifyNode(
      root,
      isRoot: true,
      nodes: nodes,
      visited: &visited,
      family: materialization.descriptor.family,
      profile: profile
    )
    guard visited.count == nodes.count else {
      throw .persistedStateCorrupt(
        reason: "A projection materialization contains unreachable nodes."
      )
    }
    let sequenceDigest = try DesignProjectionTreeBuilder().semanticSequenceDigest(
      family: materialization.descriptor.family,
      semanticVersion: materialization.descriptor.semanticVersion,
      entries: entries,
      using: digester
    )
    let semanticAccumulator = try DesignProjectionSemanticAccumulator.make(
      family: materialization.descriptor.family,
      semanticVersion: materialization.descriptor.semanticVersion,
      entries: entries,
      using: digester
    )
    guard UInt64(entries.count) == materialization.descriptor.entryCount,
          entries.first?.key == materialization.descriptor.minimumKey,
          entries.last?.key == materialization.descriptor.maximumKey,
          sequenceDigest == materialization.descriptor.canonicalSequenceDigest,
          semanticAccumulator == materialization.semanticAccumulator,
          root.level == materialization.rootLevel,
          root.subtreeNodeCount == materialization.totalNodeCount else {
      throw .persistedStateCorrupt(
        reason: "A projection tree does not match its semantic descriptor."
      )
    }
    let descriptorDigest = try DesignProjectionTreeBuilder().semanticDescriptorDigest(
      materialization.descriptor,
      using: digester
    )
    guard descriptorDigest == materialization.descriptorDigest,
          descriptorDigest == materialization.reference.semanticDescriptorDigest else {
      throw .persistedStateCorrupt(
        reason: "A projection descriptor digest does not match its binding."
      )
    }
  }

  private func verifyNode(
    _ node: DesignProjectionPhysicalNode,
    isRoot: Bool,
    nodes: [ContentDigest: DesignProjectionPhysicalNode],
    visited: inout Set<ContentDigest>,
    family: DesignProjectionFamily,
    profile: DesignProjectionPhysicalProfile
  ) throws(DesignDatabaseRuntimeError) -> [DesignProjectionEntry] {
    guard visited.insert(node.digest).inserted else {
      throw .persistedStateCorrupt(reason: "A projection tree contains a cycle or duplicate edge.")
    }
    guard node.family == family,
          node.codecVersion == profile.codecVersion,
          node.payload.count <= profile.maximumNodePayloadByteCount else {
      throw .persistedStateCorrupt(reason: "A projection node violates its physical profile.")
    }
    switch node.kind {
    case .leaf:
      guard node.level == 0, node.children.isEmpty else {
        throw .persistedStateCorrupt(reason: "A projection leaf has invalid structure.")
      }
      if !isRoot {
        guard node.entries.count >= profile.minimumLeafEntryCount,
              node.entries.count <= profile.maximumLeafEntryCount else {
          throw .persistedStateCorrupt(reason: "A projection leaf violates occupancy.")
        }
      } else if node.entries.count > profile.maximumLeafEntryCount {
        throw .persistedStateCorrupt(reason: "A projection root leaf exceeds occupancy.")
      }
      for index in node.entries.indices.dropFirst() where
        !(node.entries[index - 1].key < node.entries[index].key) {
        throw .persistedStateCorrupt(reason: "Projection leaf entries are not strictly ordered.")
      }
      guard node.subtreeEntryCount == UInt64(node.entries.count),
            node.subtreeNodeCount == 1,
            node.minimumKey == node.entries.first?.key,
            node.maximumKey == node.entries.last?.key,
            try DesignProjectionNodeCodec.decodeLeaf(node.payload) == node.entries else {
        throw .persistedStateCorrupt(reason: "A projection leaf payload is inconsistent.")
      }
      return node.entries

    case .internal:
      guard node.level > 0, node.entries.isEmpty else {
        throw .persistedStateCorrupt(reason: "A projection internal node has invalid structure.")
      }
      let minimumChildren = isRoot ? 2 : profile.minimumInternalChildCount
      guard node.children.count >= minimumChildren,
            node.children.count <= profile.maximumInternalChildCount,
            try DesignProjectionNodeCodec.decodeInternal(node.payload) == node.children else {
        throw .persistedStateCorrupt(reason: "A projection internal node violates occupancy or payload integrity.")
      }
      var entries: [DesignProjectionEntry] = []
      var entryCount: UInt64 = 0
      var descendantNodeCount: UInt64 = 0
      for (index, reference) in node.children.enumerated() {
        guard let child = nodes[reference.nodeDigest],
              child.level + 1 == node.level,
              child.minimumKey == reference.minimumKey,
              child.maximumKey == reference.maximumKey,
              child.subtreeEntryCount == reference.subtreeEntryCount,
              child.subtreeNodeCount == reference.subtreeNodeCount else {
          throw .persistedStateCorrupt(reason: "A projection child reference is inconsistent.")
        }
        if index > 0 {
          guard node.children[index - 1].maximumKey < reference.minimumKey else {
            throw .persistedStateCorrupt(reason: "Projection child key ranges overlap or are unordered.")
          }
        }
        let childEntries = try verifyNode(
          child,
          isRoot: false,
          nodes: nodes,
          visited: &visited,
          family: family,
          profile: profile
        )
        entries.append(contentsOf: childEntries)
        let (next, overflow) = entryCount.addingReportingOverflow(reference.subtreeEntryCount)
        guard !overflow else {
          throw .persistedStateCorrupt(reason: "A projection subtree count overflowed.")
        }
        entryCount = next
        let (nextNodeCount, nodeOverflow) = descendantNodeCount
          .addingReportingOverflow(reference.subtreeNodeCount)
        guard !nodeOverflow else {
          throw .persistedStateCorrupt(reason: "A projection subtree node count overflowed.")
        }
        descendantNodeCount = nextNodeCount
      }
      let (nodeCount, nodeOverflow) = descendantNodeCount.addingReportingOverflow(1)
      guard !nodeOverflow else {
        throw .persistedStateCorrupt(reason: "A projection subtree node count overflowed.")
      }
      guard node.minimumKey == node.children.first?.minimumKey,
            node.maximumKey == node.children.last?.maximumKey,
            node.subtreeEntryCount == entryCount,
            node.subtreeNodeCount == nodeCount else {
        throw .persistedStateCorrupt(reason: "A projection internal range is inconsistent.")
      }
      return entries
    }
  }
}
