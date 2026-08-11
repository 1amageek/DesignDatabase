import CircuiteFoundation
import DesignDatabaseCore

package struct DesignProjectionTreeBuilder: Sendable {
  package init() {}

  package func build(
    family: DesignProjectionFamily,
    entries: [DesignProjectionEntry],
    bindingGeneration: UInt64 = 1,
    semanticVersion: DesignProjectionSemanticVersion = .init(major: 2, minor: 0),
    profile: DesignProjectionPhysicalProfile = .checkedDefault,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionTreeMaterialization {
    let ordered = entries.sorted()
    for index in ordered.indices.dropFirst() where
      ordered[index - 1].key == ordered[index].key {
      throw .persistedStateCorrupt(
        reason: "A semantic projection contains a duplicate canonical key."
      )
    }
    guard let entryCount = UInt64(exactly: ordered.count) else {
      throw .persistedStateCorrupt(
        reason: "A semantic projection entry count exceeds UInt64."
      )
    }
    guard semanticVersion.major == 2 else {
      throw .frameworkConfigurationFailed(
        reason: "Projection semantic map construction requires semantic version 2."
      )
    }
    guard profile.codecVersion.major == 2 else {
      throw .frameworkConfigurationFailed(
        reason: "Projection tree construction requires physical codec version 2."
      )
    }
    let semanticAccumulator = try DesignProjectionSemanticAccumulator.make(
      family: family,
      semanticVersion: semanticVersion,
      entries: ordered,
      using: digester
    )
    let sequenceDigest = try semanticAccumulator.sequenceDigest(
      family: family,
      semanticVersion: semanticVersion,
      entryCount: entryCount,
      using: digester
    )
    let descriptor: DesignProjectionSemanticDescriptor
    do {
      descriptor = try DesignProjectionSemanticDescriptor(
        family: family,
        semanticVersion: semanticVersion,
        entryCount: entryCount,
        minimumKey: ordered.first?.key,
        maximumKey: ordered.last?.key,
        canonicalSequenceDigest: sequenceDigest
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A semantic projection descriptor is invalid."
      )
    }
    let descriptorDigest = try semanticDescriptorDigest(
      descriptor,
      using: digester
    )
    let profileDigest = try physicalProfileDigest(profile, using: digester)

    var nodesByDigest: [ContentDigest: DesignProjectionPhysicalNode] = [:]
    var levelNodes: [DesignProjectionPhysicalNode] = []
    if ordered.isEmpty {
      let root = try makeLeaf(
        entries: [],
        family: family,
        profile: profile,
        profileDigest: profileDigest,
        digester: digester
      )
      nodesByDigest[root.digest] = root
      levelNodes = [root]
    } else {
      let sizes = partitionSizes(
        total: ordered.count,
        maximum: profile.maximumLeafEntryCount,
        minimum: profile.minimumLeafEntryCount
      )
      var offset = 0
      for size in sizes {
        let node = try makeLeaf(
          entries: Array(ordered[offset..<(offset + size)]),
          family: family,
          profile: profile,
          profileDigest: profileDigest,
          digester: digester
        )
        nodesByDigest[node.digest] = node
        levelNodes.append(node)
        offset += size
      }
    }

    while levelNodes.count > 1 {
      let sizes = partitionSizes(
        total: levelNodes.count,
        maximum: profile.maximumInternalChildCount,
        minimum: profile.minimumInternalChildCount
      )
      var nextLevel: [DesignProjectionPhysicalNode] = []
      var offset = 0
      for size in sizes {
        var children: [DesignProjectionChildReference] = []
        children.reserveCapacity(size)
        for node in levelNodes[offset..<(offset + size)] {
          guard let reference = node.childReference else {
            throw .persistedStateCorrupt(
              reason: "An empty projection node cannot be an internal child."
            )
          }
          children.append(reference)
        }
        let node = try makeInternal(
          children: children,
          family: family,
          profile: profile,
          profileDigest: profileDigest,
          digester: digester
        )
        nodesByDigest[node.digest] = node
        nextLevel.append(node)
        offset += size
      }
      levelNodes = nextLevel
    }
    guard let root = levelNodes.first else {
      throw .persistedStateCorrupt(reason: "A projection build did not produce a root node.")
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
      throw .persistedStateCorrupt(reason: "A projection materialization reference is invalid.")
    }
    let materialization = DesignProjectionTreeMaterialization(
      descriptor: descriptor,
      descriptorDigest: descriptorDigest,
      semanticAccumulator: semanticAccumulator,
      reference: reference,
      rootLevel: root.level,
      totalNodeCount: UInt64(nodesByDigest.count),
      nodes: nodesByDigest.values.sorted {
        DesignProjectionTreeMaterialization.digestKey($0.digest)
          < DesignProjectionTreeMaterialization.digestKey($1.digest)
      }
    )
    try DesignProjectionTreeVerifier().verify(
      materialization,
      profile: profile,
      using: digester
    )
    return materialization
  }

  package func semanticSequenceDigest(
    family: DesignProjectionFamily,
    semanticVersion: DesignProjectionSemanticVersion,
    entries: [DesignProjectionEntry],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard semanticVersion.major == 2,
          let count = UInt64(exactly: entries.count) else {
      throw .persistedStateCorrupt(reason: "A semantic projection entry count exceeds UInt64.")
    }
    let accumulator = try DesignProjectionSemanticAccumulator.make(
      family: family,
      semanticVersion: semanticVersion,
      entries: entries,
      using: digester
    )
    return try accumulator.sequenceDigest(
      family: family,
      semanticVersion: semanticVersion,
      entryCount: count,
      using: digester
    )
  }

  package func semanticDescriptorDigest(
    _ descriptor: DesignProjectionSemanticDescriptor,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.ProjectionSemanticDescriptor"
    )
    encoder.append(descriptor.family.rawValue)
    encoder.append(descriptor.semanticVersion.major)
    encoder.append(descriptor.semanticVersion.minor)
    encoder.append(descriptor.entryCount)
    encoder.append(descriptor.minimumKey == nil ? UInt16(0) : UInt16(1))
    if let minimumKey = descriptor.minimumKey { encoder.append(minimumKey.bytes) }
    encoder.append(descriptor.maximumKey == nil ? UInt16(0) : UInt16(1))
    if let maximumKey = descriptor.maximumKey { encoder.append(maximumKey.bytes) }
    encoder.append(descriptor.canonicalSequenceDigest)
    return try encoder.finalize(using: digester)
  }

  package func physicalProfileDigest(
    _ profile: DesignProjectionPhysicalProfile,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.ProjectionPhysicalProfile"
    )
    encoder.append(profile.codecVersion.major)
    encoder.append(profile.codecVersion.minor)
    encoder.append(UInt64(profile.maximumLeafEntryCount))
    encoder.append(UInt64(profile.minimumLeafEntryCount))
    encoder.append(UInt64(profile.maximumInternalChildCount))
    encoder.append(UInt64(profile.minimumInternalChildCount))
    encoder.append(UInt64(profile.maximumNodePayloadByteCount))
    return try encoder.finalize(using: digester)
  }

  package func makeLeaf(
    entries: [DesignProjectionEntry],
    family: DesignProjectionFamily,
    profile: DesignProjectionPhysicalProfile,
    profileDigest: ContentDigest,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionPhysicalNode {
    let payload = try DesignProjectionNodeCodec.encodeLeaf(entries)
    try requirePayloadBudget(payload, profile: profile)
    let count = UInt64(entries.count)
    let digest = try nodeDigest(
      family: family,
      codecVersion: profile.codecVersion,
      profileDigest: profileDigest,
      kind: .leaf,
      level: 0,
      minimumKey: entries.first?.key,
      maximumKey: entries.last?.key,
      subtreeEntryCount: count,
      subtreeNodeCount: 1,
      payload: payload,
      using: digester
    )
    return DesignProjectionPhysicalNode(
      digest: digest,
      family: family,
      codecVersion: profile.codecVersion,
      physicalProfileDigest: profileDigest,
      kind: .leaf,
      level: 0,
      minimumKey: entries.first?.key,
      maximumKey: entries.last?.key,
      subtreeEntryCount: count,
      subtreeNodeCount: 1,
      entries: entries,
      children: [],
      payload: payload
    )
  }

  package func makeInternal(
    children: [DesignProjectionChildReference],
    family: DesignProjectionFamily,
    profile: DesignProjectionPhysicalProfile,
    profileDigest: ContentDigest,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionPhysicalNode {
    guard let first = children.first, let last = children.last else {
      throw .persistedStateCorrupt(reason: "An internal projection node has no children.")
    }
    var entryCount: UInt64 = 0
    var descendantNodeCount: UInt64 = 0
    for child in children {
      let (next, overflow) = entryCount.addingReportingOverflow(child.subtreeEntryCount)
      guard !overflow else {
        throw .persistedStateCorrupt(reason: "A projection subtree entry count overflowed.")
      }
      entryCount = next
      let (nextNodeCount, nodeOverflow) = descendantNodeCount
        .addingReportingOverflow(child.subtreeNodeCount)
      guard !nodeOverflow else {
        throw .persistedStateCorrupt(reason: "A projection subtree node count overflowed.")
      }
      descendantNodeCount = nextNodeCount
    }
    let (nodeCount, nodeOverflow) = descendantNodeCount.addingReportingOverflow(1)
    guard !nodeOverflow else {
      throw .persistedStateCorrupt(reason: "A projection subtree node count overflowed.")
    }
    let level = first.level + 1
    guard children.allSatisfy({ $0.level + 1 == level }) else {
      throw .persistedStateCorrupt(reason: "Projection children do not share one depth.")
    }
    let payload = try DesignProjectionNodeCodec.encodeInternal(children)
    try requirePayloadBudget(payload, profile: profile)
    let digest = try nodeDigest(
      family: family,
      codecVersion: profile.codecVersion,
      profileDigest: profileDigest,
      kind: .internal,
      level: level,
      minimumKey: first.minimumKey,
      maximumKey: last.maximumKey,
      subtreeEntryCount: entryCount,
      subtreeNodeCount: nodeCount,
      payload: payload,
      using: digester
    )
    return DesignProjectionPhysicalNode(
      digest: digest,
      family: family,
      codecVersion: profile.codecVersion,
      physicalProfileDigest: profileDigest,
      kind: .internal,
      level: level,
      minimumKey: first.minimumKey,
      maximumKey: last.maximumKey,
      subtreeEntryCount: entryCount,
      subtreeNodeCount: nodeCount,
      entries: [],
      children: children,
      payload: payload
    )
  }

  package func nodeDigest(
    family: DesignProjectionFamily,
    codecVersion: DesignProjectionPhysicalCodecVersion,
    profileDigest: ContentDigest,
    kind: DesignProjectionNodeKind,
    level: UInt16,
    minimumKey: DesignCanonicalKey?,
    maximumKey: DesignCanonicalKey?,
    subtreeEntryCount: UInt64,
    subtreeNodeCount: UInt64,
    payload: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.ProjectionPhysicalNode"
    )
    encoder.append(family.rawValue)
    encoder.append(codecVersion.major)
    encoder.append(codecVersion.minor)
    encoder.append(profileDigest)
    encoder.append(UInt64(kind.rawValue))
    encoder.append(level)
    encoder.append(minimumKey == nil ? UInt16(0) : UInt16(1))
    if let minimumKey { encoder.append(minimumKey.bytes) }
    encoder.append(maximumKey == nil ? UInt16(0) : UInt16(1))
    if let maximumKey { encoder.append(maximumKey.bytes) }
    encoder.append(subtreeEntryCount)
    encoder.append(subtreeNodeCount)
    encoder.append(payload)
    return try encoder.finalize(using: digester)
  }

  private func requirePayloadBudget(
    _ payload: [UInt8],
    profile: DesignProjectionPhysicalProfile
  ) throws(DesignDatabaseRuntimeError) {
    guard payload.count <= profile.maximumNodePayloadByteCount else {
      throw .frameworkConfigurationFailed(
        reason: "A projection node exceeds the physical profile byte budget."
      )
    }
  }

  private func partitionSizes(
    total: Int,
    maximum: Int,
    minimum: Int
  ) -> [Int] {
    precondition(total > 0)
    if total <= maximum { return [total] }
    let groupCount = (total + maximum - 1) / maximum
    let base = total / groupCount
    let remainder = total % groupCount
    precondition(base >= minimum)
    return (0..<groupCount).map { $0 < remainder ? base + 1 : base }
  }
}
