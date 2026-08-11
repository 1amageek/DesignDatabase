import CircuiteFoundation
import DesignDatabaseCore

package enum DesignProjectionPersistedNodeDecoder {
  package static func decode(
    _ model: DesignProjectionNodeModel,
    expectedDigest: ContentDigest,
    family: DesignProjectionFamily,
    reference: DesignProjectionMaterializationReference,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionPhysicalNode {
    try validateIdentity(
      model,
      expectedDigest: expectedDigest,
      family: family,
      reference: reference
    )
    guard let kind = DesignProjectionNodeKind(rawValue: model.nodeKind),
          let level = UInt16(exactly: model.level),
          let subtreeEntryCount = UInt64(model.subtreeEntryCount),
          let subtreeNodeCount = UInt64(model.subtreeNodeCount),
          subtreeNodeCount > 0,
          let itemCount = Int(exactly: model.itemCount),
          let encodedByteCount = Int(model.encodedByteCount),
          itemCount >= 0,
          encodedByteCount >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A projection node contains invalid numeric metadata."
      )
    }
    let payload = Array(model.payload)
    guard payload.count == encodedByteCount else {
      throw .persistedStateCorrupt(
        reason: "A projection node payload byte count is inconsistent."
      )
    }
    let minimumKey = try decodeOptionalKey(model.minimumKey)
    let maximumKey = try decodeOptionalKey(model.maximumKey)
    let entries: [DesignProjectionEntry]
    let children: [DesignProjectionChildReference]
    switch kind {
    case .leaf:
      entries = try DesignProjectionNodeCodec.decodeLeaf(payload)
      children = []
      guard entries.count == itemCount else {
        throw .persistedStateCorrupt(
          reason: "A projection leaf item count is inconsistent."
        )
      }
    case .internal:
      entries = []
      children = try DesignProjectionNodeCodec.decodeInternal(payload)
      guard children.count == itemCount else {
        throw .persistedStateCorrupt(
          reason: "A projection internal item count is inconsistent."
        )
      }
    }
    let actualDigest = try DesignProjectionTreeBuilder().nodeDigest(
      family: family,
      codecVersion: reference.physicalCodecVersion,
      profileDigest: reference.physicalProfileDigest,
      kind: kind,
      level: level,
      minimumKey: minimumKey,
      maximumKey: maximumKey,
      subtreeEntryCount: subtreeEntryCount,
      subtreeNodeCount: subtreeNodeCount,
      payload: payload,
      using: digester
    )
    guard actualDigest == expectedDigest else {
      throw .persistedStateCorrupt(
        reason: "A projection node digest does not match its persisted payload."
      )
    }
    return DesignProjectionPhysicalNode(
      digest: expectedDigest,
      family: family,
      codecVersion: reference.physicalCodecVersion,
      physicalProfileDigest: reference.physicalProfileDigest,
      kind: kind,
      level: level,
      minimumKey: minimumKey,
      maximumKey: maximumKey,
      subtreeEntryCount: subtreeEntryCount,
      subtreeNodeCount: subtreeNodeCount,
      entries: entries,
      children: children,
      payload: payload
    )
  }

  package static func validateIdentity(
    _ model: DesignProjectionNodeModel,
    expectedDigest: ContentDigest,
    family: DesignProjectionFamily,
    reference: DesignProjectionMaterializationReference
  ) throws(DesignDatabaseRuntimeError) {
    guard model.id == DesignProjectionTreeMaterialization.digestKey(expectedDigest),
          model.family == family.rawValue,
          model.physicalCodecMajor == Int64(reference.physicalCodecVersion.major),
          model.physicalCodecMinor == Int64(reference.physicalCodecVersion.minor),
          model.physicalProfileDigestAlgorithm == reference.physicalProfileDigest.algorithm.rawValue,
          model.physicalProfileDigestValue == reference.physicalProfileDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A projection node identity does not match its materialization."
      )
    }
  }

  private static func decodeOptionalKey(
    _ value: String
  ) throws(DesignDatabaseRuntimeError) -> DesignCanonicalKey? {
    guard !value.isEmpty else { return nil }
    do {
      return try DesignCanonicalKey(
        bytes: DesignProjectionTreeMaterialization.bytes(hexadecimal: value)
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection node key bound is invalid."
      )
    }
  }
}
