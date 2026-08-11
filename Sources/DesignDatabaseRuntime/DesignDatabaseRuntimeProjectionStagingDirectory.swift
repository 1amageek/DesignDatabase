import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeProjectionStagingDirectory: Sendable {
  package struct Entry: Sendable {
    package let materialization: DesignProjectionTreeMaterialization
    package let models: DesignProjectionPersistedModels
    package let startIndex: UInt64
    package let endIndex: UInt64
  }

  package struct NodeWrite: Sendable {
    package let materialization: DesignProjectionTreeMaterialization
    package let node: DesignProjectionPhysicalNode
    package let model: DesignProjectionNodeModel
  }

  package let entries: [Entry]
  package let totalNodeCount: UInt64

  package init(
    _ materializations: [DesignProjectionTreeMaterialization],
    databaseID: DesignDatabaseID,
    revision: DesignRevisionReference
  ) throws(DesignDatabaseRuntimeError) {
    let ordered = materializations.sorted {
      $0.descriptor.family < $1.descriptor.family
    }
    guard !ordered.isEmpty else {
      throw .persistedStateCorrupt(
        reason: "A candidate revision must publish at least one semantic projection."
      )
    }
    for index in ordered.indices.dropFirst() where
      ordered[index - 1].descriptor.family == ordered[index].descriptor.family {
      throw .persistedStateCorrupt(
        reason: "A candidate revision contains duplicate projection families."
      )
    }

    var nextIndex: UInt64 = 0
    var entries: [Entry] = []
    entries.reserveCapacity(ordered.count)
    for materialization in ordered {
      let models = try materialization.models(
        databaseID: databaseID,
        revision: revision
      )
      guard models.nodes.count == materialization.nodes.count,
            let nodeCount = UInt64(exactly: materialization.nodes.count),
            materialization.totalNodeCount > 0,
            nodeCount <= materialization.totalNodeCount else {
        throw .persistedStateCorrupt(
          reason: "A projection staging directory has inconsistent node counts."
        )
      }
      let (endIndex, overflow) = nextIndex.addingReportingOverflow(nodeCount)
      guard !overflow else {
        throw .commitTransactionFailed(
          reason: "The projection staging node count overflowed."
        )
      }
      entries.append(
        Entry(
          materialization: materialization,
          models: models,
          startIndex: nextIndex,
          endIndex: endIndex
        )
      )
      nextIndex = endIndex
    }
    self.entries = entries
    totalNodeCount = nextIndex
  }

  package var materializations: [DesignProjectionTreeMaterialization] {
    entries.map(\.materialization)
  }

  package var descriptors: [DesignProjectionSemanticDescriptor] {
    entries.map(\.materialization.descriptor)
  }

  package func resolve(
    _ globalIndex: UInt64
  ) throws(DesignDatabaseRuntimeError) -> NodeWrite {
    guard globalIndex < totalNodeCount else {
      throw .persistedStateCorrupt(
        reason: "A projection staging index is outside the prepared directory."
      )
    }
    guard let entry = entries.first(where: {
      globalIndex >= $0.startIndex && globalIndex < $0.endIndex
    }) else {
      throw .persistedStateCorrupt(
        reason: "A projection staging index has no owning materialization."
      )
    }
    let localIndexValue = globalIndex - entry.startIndex
    guard let localIndex = Int(exactly: localIndexValue),
          localIndex < entry.materialization.nodes.count,
          localIndex < entry.models.nodes.count else {
      throw .persistedStateCorrupt(
        reason: "A projection staging local index is not representable."
      )
    }
    return NodeWrite(
      materialization: entry.materialization,
      node: entry.materialization.nodes[localIndex],
      model: entry.models.nodes[localIndex]
    )
  }
}
