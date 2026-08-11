import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionTreeUpdater: Sendable {
  package enum Outcome: Sendable {
    case updated(DesignProjectionTreeMaterialization)
    case rejected(String)
    case budgetExceeded(limit: UInt64, requested: UInt64)
  }

  package init() {}

  package func update(
    base: DesignProjectionRuntimeMaterialization,
    changes: [DesignProjectionChange],
    reads: DesignDatabaseRuntimeReadSnapshot,
    profile: DesignProjectionPhysicalProfile = .checkedDefault,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> Outcome {
    guard !changes.isEmpty else {
      return .rejected("A projection update must contain at least one change.")
    }
    guard base.descriptor.semanticVersion.major == 2,
          base.reference.physicalCodecVersion.major == 2,
          profile.codecVersion == base.reference.physicalCodecVersion else {
      return .rejected(
        "An existing projection must use semantic version 2 and physical codec version 2 before path-copy mutation."
      )
    }
    let profileDigest = try DesignProjectionTreeBuilder().physicalProfileDigest(
      profile,
      using: digester
    )
    guard profileDigest == base.reference.physicalProfileDigest else {
      return .rejected(
        "The existing projection physical profile is unavailable to the path-copy updater."
      )
    }
    let ordered = changes.sorted()
    for index in ordered.indices {
      guard ordered[index].family == base.descriptor.family else {
        return .rejected(
          "A path-copy update cannot cross projection-family boundaries."
        )
      }
      if index > ordered.startIndex,
         ordered[index - 1].key == ordered[index].key {
        return .rejected(
          "A path-copy update contains duplicate canonical keys."
        )
      }
    }

    var workspace = Workspace(
      base: base,
      reads: reads,
      profile: profile,
      profileDigest: profileDigest,
      digester: digester
    )
    do {
      return .updated(try await workspace.apply(ordered))
    } catch let rejection as Rejection {
      return .rejected(rejection.reason)
    } catch let readError as DesignDatabaseRuntimeReadError {
      switch readError {
      case .budgetExceeded(let limit, let requested):
        return .budgetExceeded(limit: limit, requested: requested)
      case .invalidReadCount(let count):
        throw .persistedStateCorrupt(
          reason: "A projection path-copy read requested an invalid count: \(count)."
        )
      case .snapshotClosed:
        throw .persistedStateCorrupt(
          reason: "A projection path-copy read used a closed validation snapshot."
        )
      }
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }
}

private extension DesignProjectionTreeUpdater {
  struct Rejection: Error {
    let reason: String
  }

  struct Workspace {
    let base: DesignProjectionRuntimeMaterialization
    let reads: DesignDatabaseRuntimeReadSnapshot
    let profile: DesignProjectionPhysicalProfile
    let profileDigest: ContentDigest
    let digester: any ContentDigesting

    var rootDigest: ContentDigest
    var accumulator: DesignProjectionSemanticAccumulator
    var persistedNodeCache: [ContentDigest: DesignProjectionPhysicalNode] = [:]
    var newNodes: [ContentDigest: DesignProjectionPhysicalNode] = [:]

    init(
      base: DesignProjectionRuntimeMaterialization,
      reads: DesignDatabaseRuntimeReadSnapshot,
      profile: DesignProjectionPhysicalProfile,
      profileDigest: ContentDigest,
      digester: any ContentDigesting
    ) {
      self.base = base
      self.reads = reads
      self.profile = profile
      self.profileDigest = profileDigest
      self.digester = digester
      rootDigest = base.reference.rootNodeDigest
      accumulator = base.semanticAccumulator
    }

    mutating func apply(
      _ changes: [DesignProjectionChange]
    ) async throws -> DesignProjectionTreeMaterialization {
      var entryCount = base.descriptor.entryCount
      for change in changes {
        let root = try await fetchNode(rootDigest)
        let replacements = try await mutate(
          root,
          change: change,
          isRoot: true
        )
        let normalizedRoot = try await normalizeRoot(replacements)
        rootDigest = normalizedRoot.digest

        if let before = change.before {
          accumulator = try accumulator.removing(
            before,
            family: base.descriptor.family,
            semanticVersion: base.descriptor.semanticVersion,
            using: digester
          )
          guard entryCount > 0 else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A projection path-copy entry count underflowed."
            )
          }
          entryCount -= 1
        }
        if let after = change.after {
          accumulator = try accumulator.adding(
            after,
            family: base.descriptor.family,
            semanticVersion: base.descriptor.semanticVersion,
            using: digester
          )
          let (next, overflow) = entryCount.addingReportingOverflow(1)
          guard !overflow else {
            throw DesignDatabaseRuntimeError.persistedStateCorrupt(
              reason: "A projection path-copy entry count overflowed."
            )
          }
          entryCount = next
        }
      }

      let root = try await fetchNode(rootDigest)
      guard root.subtreeEntryCount == entryCount else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A path-copied projection root has an inconsistent entry count."
        )
      }
      let sequenceDigest = try accumulator.sequenceDigest(
        family: base.descriptor.family,
        semanticVersion: base.descriptor.semanticVersion,
        entryCount: entryCount,
        using: digester
      )
      let descriptor: DesignProjectionSemanticDescriptor
      do {
        descriptor = try DesignProjectionSemanticDescriptor(
          family: base.descriptor.family,
          semanticVersion: base.descriptor.semanticVersion,
          entryCount: entryCount,
          minimumKey: root.minimumKey,
          maximumKey: root.maximumKey,
          canonicalSequenceDigest: sequenceDigest
        )
      } catch {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A path-copied projection descriptor is invalid."
        )
      }
      let descriptorDigest = try DesignProjectionTreeBuilder()
        .semanticDescriptorDigest(descriptor, using: digester)
      let (bindingGeneration, generationOverflow) = base.reference
        .bindingGeneration.addingReportingOverflow(1)
      guard !generationOverflow else {
        throw DesignDatabaseRuntimeError.generationExhausted(
          kind: "projection materialization binding"
        )
      }
      let reference: DesignProjectionMaterializationReference
      do {
        reference = try DesignProjectionMaterializationReference(
          semanticDescriptorDigest: descriptorDigest,
          bindingGeneration: bindingGeneration,
          physicalCodecVersion: profile.codecVersion,
          physicalProfileDigest: profileDigest,
          rootNodeDigest: root.digest
        )
      } catch {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A path-copied projection reference is invalid."
        )
      }
      let reachableNodes = reachableNewNodes(from: root)
      return DesignProjectionTreeMaterialization(
        descriptor: descriptor,
        descriptorDigest: descriptorDigest,
        semanticAccumulator: accumulator,
        reference: reference,
        rootLevel: root.level,
        totalNodeCount: root.subtreeNodeCount,
        nodes: reachableNodes.sorted {
          DesignProjectionTreeMaterialization.digestKey($0.digest)
            < DesignProjectionTreeMaterialization.digestKey($1.digest)
        }
      )
    }

    mutating func mutate(
      _ node: DesignProjectionPhysicalNode,
      change: DesignProjectionChange,
      isRoot: Bool
    ) async throws -> [DesignProjectionPhysicalNode] {
      switch node.kind {
      case .leaf:
        return try mutateLeaf(node, change: change, isRoot: isRoot)
      case .internal:
        return try await mutateInternal(
          node,
          change: change,
          isRoot: isRoot
        )
      }
    }

    mutating func mutateLeaf(
      _ node: DesignProjectionPhysicalNode,
      change: DesignProjectionChange,
      isRoot: Bool
    ) throws -> [DesignProjectionPhysicalNode] {
      try validateLeaf(node)
      var entries = node.entries
      let index = lowerBound(in: entries, for: change.key)
      let existing = index < entries.count && entries[index].key == change.key
        ? entries[index]
        : nil
      if let before = change.before {
        guard existing == before else {
          throw Rejection(
            reason: "A projection change before value does not match the exact base entry."
          )
        }
      } else {
        guard existing == nil else {
          throw Rejection(
            reason: "A projection insertion collides with an existing canonical key."
          )
        }
      }

      switch (existing, change.after) {
      case (.some, .some(let after)):
        entries[index] = after
      case (.some, .none):
        entries.remove(at: index)
      case (.none, .some(let after)):
        entries.insert(after, at: index)
      case (.none, .none):
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A validated projection change has no before or after value."
        )
      }

      if entries.isEmpty && !isRoot { return [] }
      return try makeLeaves(entries)
    }

    mutating func mutateInternal(
      _ node: DesignProjectionPhysicalNode,
      change: DesignProjectionChange,
      isRoot: Bool
    ) async throws -> [DesignProjectionPhysicalNode] {
      try validateInternal(node)
      var children = node.children
      let targetIndex = childIndex(in: children, for: change.key)
      let target = try await fetchChild(children[targetIndex], parent: node)
      let replacements = try await mutate(
        target,
        change: change,
        isRoot: false
      )
      children.replaceSubrange(
        targetIndex...targetIndex,
        with: replacements.compactMap(\.childReference)
      )

      if replacements.count == 1,
         let replacement = replacements.first,
         isUnderfull(replacement) {
        children = try await rebalance(
          children,
          affectedIndex: min(targetIndex, max(children.count - 1, 0))
        )
      }

      guard !children.isEmpty else { return [] }
      if isRoot, children.count == 1 {
        return [try await fetchNode(children[0].nodeDigest)]
      }
      return try makeInternalNodes(children)
    }

    mutating func rebalance(
      _ children: [DesignProjectionChildReference],
      affectedIndex: Int
    ) async throws -> [DesignProjectionChildReference] {
      guard children.count > 1 else { return children }
      let leftIndex: Int
      let rightIndex: Int
      if affectedIndex > 0 {
        leftIndex = affectedIndex - 1
        rightIndex = affectedIndex
      } else {
        leftIndex = 0
        rightIndex = 1
      }
      let left = try await fetchNode(children[leftIndex].nodeDigest)
      let right = try await fetchNode(children[rightIndex].nodeDigest)
      guard left.kind == right.kind, left.level == right.level else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "Projection rebalance siblings do not share one node kind and level."
        )
      }
      let replacements: [DesignProjectionPhysicalNode]
      switch left.kind {
      case .leaf:
        replacements = try makeLeaves(left.entries + right.entries)
      case .internal:
        replacements = try makeInternalNodes(left.children + right.children)
      }
      var result = children
      result.replaceSubrange(
        leftIndex...rightIndex,
        with: replacements.compactMap(\.childReference)
      )
      return result
    }

    mutating func normalizeRoot(
      _ replacements: [DesignProjectionPhysicalNode]
    ) async throws -> DesignProjectionPhysicalNode {
      if replacements.isEmpty {
        return try store(
          DesignProjectionTreeBuilder().makeLeaf(
            entries: [],
            family: base.descriptor.family,
            profile: profile,
            profileDigest: profileDigest,
            digester: digester
          )
        )
      }
      if replacements.count == 1 {
        return replacements[0]
      }
      guard replacements.count == 2 else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A projection path-copy root produced too many replacements."
        )
      }
      return try store(
        DesignProjectionTreeBuilder().makeInternal(
          children: replacements.compactMap(\.childReference),
          family: base.descriptor.family,
          profile: profile,
          profileDigest: profileDigest,
          digester: digester
        )
      )
    }

    mutating func makeLeaves(
      _ entries: [DesignProjectionEntry]
    ) throws -> [DesignProjectionPhysicalNode] {
      guard !entries.isEmpty else { return [] }
      let sizes = partitionSizes(
        total: entries.count,
        maximum: profile.maximumLeafEntryCount,
        minimum: profile.minimumLeafEntryCount
      )
      var result: [DesignProjectionPhysicalNode] = []
      var offset = 0
      for size in sizes {
        result.append(
          try store(
            DesignProjectionTreeBuilder().makeLeaf(
              entries: Array(entries[offset..<(offset + size)]),
              family: base.descriptor.family,
              profile: profile,
              profileDigest: profileDigest,
              digester: digester
            )
          )
        )
        offset += size
      }
      return result
    }

    mutating func makeInternalNodes(
      _ children: [DesignProjectionChildReference]
    ) throws -> [DesignProjectionPhysicalNode] {
      guard !children.isEmpty else { return [] }
      let sizes = partitionSizes(
        total: children.count,
        maximum: profile.maximumInternalChildCount,
        minimum: profile.minimumInternalChildCount
      )
      var result: [DesignProjectionPhysicalNode] = []
      var offset = 0
      for size in sizes {
        result.append(
          try store(
            DesignProjectionTreeBuilder().makeInternal(
              children: Array(children[offset..<(offset + size)]),
              family: base.descriptor.family,
              profile: profile,
              profileDigest: profileDigest,
              digester: digester
            )
          )
        )
        offset += size
      }
      return result
    }

    mutating func fetchNode(
      _ digest: ContentDigest
    ) async throws -> DesignProjectionPhysicalNode {
      if let node = newNodes[digest] { return node }
      if let node = persistedNodeCache[digest] { return node }
      guard let model = try await reads.fetch(
        DesignProjectionNodeModel.self,
        identifiedBy: DesignProjectionTreeMaterialization.digestKey(digest),
        consistency: .serializable
      ) else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A projection path-copy traversal reached a missing node."
        )
      }
      let node = try DesignProjectionPersistedNodeDecoder.decode(
        model,
        expectedDigest: digest,
        family: base.descriptor.family,
        reference: base.reference,
        digester: digester
      )
      persistedNodeCache[digest] = node
      return node
    }

    mutating func fetchChild(
      _ reference: DesignProjectionChildReference,
      parent: DesignProjectionPhysicalNode
    ) async throws -> DesignProjectionPhysicalNode {
      let child = try await fetchNode(reference.nodeDigest)
      guard child.minimumKey == reference.minimumKey,
            child.maximumKey == reference.maximumKey,
            child.subtreeEntryCount == reference.subtreeEntryCount,
            child.subtreeNodeCount == reference.subtreeNodeCount,
            child.level == reference.level,
            child.level + 1 == parent.level else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "A projection path-copy child does not match its parent reference."
        )
      }
      return child
    }

    mutating func store(
      _ node: DesignProjectionPhysicalNode
    ) -> DesignProjectionPhysicalNode {
      newNodes[node.digest] = node
      return node
    }

    func reachableNewNodes(
      from root: DesignProjectionPhysicalNode
    ) -> [DesignProjectionPhysicalNode] {
      var result: [DesignProjectionPhysicalNode] = []
      var visited: Set<ContentDigest> = []
      var pending = [root.digest]
      while let digest = pending.popLast() {
        guard visited.insert(digest).inserted,
              let node = newNodes[digest] else {
          continue
        }
        result.append(node)
        pending.append(contentsOf: node.children.map(\.nodeDigest))
      }
      return result
    }

    func validateLeaf(
      _ node: DesignProjectionPhysicalNode
    ) throws(DesignDatabaseRuntimeError) {
      guard node.level == 0,
            node.children.isEmpty,
            node.subtreeEntryCount == UInt64(node.entries.count),
            node.subtreeNodeCount == 1,
            node.minimumKey == node.entries.first?.key,
            node.maximumKey == node.entries.last?.key else {
        throw .persistedStateCorrupt(
          reason: "A projection path-copy leaf has inconsistent metadata."
        )
      }
      for index in node.entries.indices.dropFirst() where
        !(node.entries[index - 1].key < node.entries[index].key) {
        throw .persistedStateCorrupt(
          reason: "A projection path-copy leaf is not strictly ordered."
        )
      }
    }

    func validateInternal(
      _ node: DesignProjectionPhysicalNode
    ) throws(DesignDatabaseRuntimeError) {
      guard node.level > 0,
            node.entries.isEmpty,
            !node.children.isEmpty,
            node.minimumKey == node.children.first?.minimumKey,
            node.maximumKey == node.children.last?.maximumKey else {
        throw .persistedStateCorrupt(
          reason: "A projection path-copy internal node has inconsistent metadata."
        )
      }
      var entryCount: UInt64 = 0
      var descendantNodeCount: UInt64 = 0
      for index in node.children.indices {
        let child = node.children[index]
        guard child.minimumKey <= child.maximumKey,
              child.level + 1 == node.level,
              child.subtreeNodeCount > 0 else {
          throw .persistedStateCorrupt(
            reason: "A projection path-copy child reference is malformed."
          )
        }
        if index > node.children.startIndex,
           !(node.children[index - 1].maximumKey < child.minimumKey) {
          throw .persistedStateCorrupt(
            reason: "Projection path-copy child ranges overlap or are unordered."
          )
        }
        entryCount = try adding(entryCount, child.subtreeEntryCount)
        descendantNodeCount = try adding(
          descendantNodeCount,
          child.subtreeNodeCount
        )
      }
      let nodeCount = try adding(descendantNodeCount, 1)
      guard node.subtreeEntryCount == entryCount,
            node.subtreeNodeCount == nodeCount else {
        throw .persistedStateCorrupt(
          reason: "A projection path-copy internal subtree count is inconsistent."
        )
      }
    }

    func isUnderfull(_ node: DesignProjectionPhysicalNode) -> Bool {
      switch node.kind {
      case .leaf:
        node.entries.count < profile.minimumLeafEntryCount
      case .internal:
        node.children.count < profile.minimumInternalChildCount
      }
    }

    func childIndex(
      in children: [DesignProjectionChildReference],
      for key: DesignCanonicalKey
    ) -> Int {
      var lower = 0
      var upper = children.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if children[middle].maximumKey < key {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      return min(lower, children.count - 1)
    }

    func lowerBound(
      in entries: [DesignProjectionEntry],
      for key: DesignCanonicalKey
    ) -> Int {
      var lower = 0
      var upper = entries.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if entries[middle].key < key {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      return lower
    }

    func partitionSizes(
      total: Int,
      maximum: Int,
      minimum: Int
    ) -> [Int] {
      precondition(total > 0)
      if total <= maximum { return [total] }
      let groupCount = (total + maximum - 1) / maximum
      let baseSize = total / groupCount
      let remainder = total % groupCount
      precondition(baseSize >= minimum)
      return (0..<groupCount).map {
        $0 < remainder ? baseSize + 1 : baseSize
      }
    }

    func adding(
      _ lhs: UInt64,
      _ rhs: UInt64
    ) throws(DesignDatabaseRuntimeError) -> UInt64 {
      let (result, overflow) = lhs.addingReportingOverflow(rhs)
      guard !overflow else {
        throw .persistedStateCorrupt(
          reason: "A projection path-copy subtree count overflowed."
        )
      }
      return result
    }
  }
}
