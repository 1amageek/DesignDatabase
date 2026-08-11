import CircuiteFoundation
import Database
import DesignDatabaseCore

package struct DesignProjectionTreeMaterialization: Sendable {
  package let descriptor: DesignProjectionSemanticDescriptor
  package let descriptorDigest: ContentDigest
  package let semanticAccumulator: DesignProjectionSemanticAccumulator
  package let reference: DesignProjectionMaterializationReference
  package let rootLevel: UInt16
  package let totalNodeCount: UInt64
  package let nodes: [DesignProjectionPhysicalNode]

  package func models(
    databaseID: DesignDatabaseID,
    revision: DesignRevisionReference
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionPersistedModels {
    guard revision.databaseID == databaseID else {
      throw .persistedStateCorrupt(
        reason: "A projection materialization crossed a database boundary."
      )
    }
    let family = descriptor.family.rawValue
    let bindingID = revision.revisionID.description + ":" + family

    var descriptorModel = DesignProjectionSemanticDescriptorModel()
    descriptorModel.id = bindingID
    descriptorModel.databaseID = databaseID.description
    descriptorModel.revisionID = revision.revisionID.description
    descriptorModel.family = family
    descriptorModel.semanticVersionMajor = Int64(descriptor.semanticVersion.major)
    descriptorModel.semanticVersionMinor = Int64(descriptor.semanticVersion.minor)
    descriptorModel.entryCount = String(descriptor.entryCount)
    descriptorModel.minimumKey = Self.hexadecimal(descriptor.minimumKey?.bytes ?? [])
    descriptorModel.maximumKey = Self.hexadecimal(descriptor.maximumKey?.bytes ?? [])
    descriptorModel.sequenceDigestAlgorithm = descriptor.canonicalSequenceDigest.algorithm.rawValue
    descriptorModel.sequenceDigestValue = descriptor.canonicalSequenceDigest.hexadecimalValue
    descriptorModel.accumulatorFirst = Self.hexadecimal(semanticAccumulator.first)
    descriptorModel.accumulatorSecond = Self.hexadecimal(semanticAccumulator.second)
    descriptorModel.descriptorDigestAlgorithm = descriptorDigest.algorithm.rawValue
    descriptorModel.descriptorDigestValue = descriptorDigest.hexadecimalValue

    var bindingModel = DesignProjectionBindingModel()
    bindingModel.id = bindingID
    bindingModel.databaseID = databaseID.description
    bindingModel.revisionID = revision.revisionID.description
    bindingModel.family = family
    bindingModel.semanticDescriptorDigestAlgorithm = reference.semanticDescriptorDigest.algorithm.rawValue
    bindingModel.semanticDescriptorDigestValue = reference.semanticDescriptorDigest.hexadecimalValue
    bindingModel.bindingGeneration = String(reference.bindingGeneration)
    bindingModel.physicalCodecMajor = Int64(reference.physicalCodecVersion.major)
    bindingModel.physicalCodecMinor = Int64(reference.physicalCodecVersion.minor)
    bindingModel.physicalProfileDigestAlgorithm = reference.physicalProfileDigest.algorithm.rawValue
    bindingModel.physicalProfileDigestValue = reference.physicalProfileDigest.hexadecimalValue
    bindingModel.rootNodeDigestAlgorithm = reference.rootNodeDigest.algorithm.rawValue
    bindingModel.rootNodeDigestValue = reference.rootNodeDigest.hexadecimalValue

    var materializationModel = DesignProjectionMaterializationModel()
    materializationModel.id = bindingID + ":" + String(reference.bindingGeneration)
    materializationModel.databaseID = databaseID.description
    materializationModel.revisionID = revision.revisionID.description
    materializationModel.family = family
    materializationModel.semanticDescriptorDigestAlgorithm = reference.semanticDescriptorDigest.algorithm.rawValue
    materializationModel.semanticDescriptorDigestValue = reference.semanticDescriptorDigest.hexadecimalValue
    materializationModel.bindingGeneration = String(reference.bindingGeneration)
    materializationModel.physicalCodecMajor = Int64(reference.physicalCodecVersion.major)
    materializationModel.physicalCodecMinor = Int64(reference.physicalCodecVersion.minor)
    materializationModel.physicalProfileDigestAlgorithm = reference.physicalProfileDigest.algorithm.rawValue
    materializationModel.physicalProfileDigestValue = reference.physicalProfileDigest.hexadecimalValue
    materializationModel.rootNodeDigestAlgorithm = reference.rootNodeDigest.algorithm.rawValue
    materializationModel.rootNodeDigestValue = reference.rootNodeDigest.hexadecimalValue
    materializationModel.treeHeight = Int64(rootLevel) + 1
    materializationModel.nodeCount = String(totalNodeCount)
    materializationModel.entryCount = String(descriptor.entryCount)
    materializationModel.verificationState = 1

    let nodeModels = nodes.map { node in
      var model = DesignProjectionNodeModel()
      model.id = Self.digestKey(node.digest)
      model.family = node.family.rawValue
      model.physicalCodecMajor = Int64(node.codecVersion.major)
      model.physicalCodecMinor = Int64(node.codecVersion.minor)
      model.physicalProfileDigestAlgorithm = node.physicalProfileDigest.algorithm.rawValue
      model.physicalProfileDigestValue = node.physicalProfileDigest.hexadecimalValue
      model.nodeKind = node.kind.rawValue
      model.level = Int64(node.level)
      model.minimumKey = Self.hexadecimal(node.minimumKey?.bytes ?? [])
      model.maximumKey = Self.hexadecimal(node.maximumKey?.bytes ?? [])
      model.subtreeEntryCount = String(node.subtreeEntryCount)
      model.subtreeNodeCount = String(node.subtreeNodeCount)
      model.itemCount = Int64(node.itemCount)
      model.payload = ByteString(node.payload)
      model.encodedByteCount = String(node.payload.count)
      return model
    }
    return DesignProjectionPersistedModels(
      descriptor: descriptorModel,
      binding: bindingModel,
      materialization: materializationModel,
      nodes: nodeModels
    )
  }

  package static func digestKey(_ digest: ContentDigest) -> String {
    digest.algorithm.rawValue + ":" + digest.hexadecimalValue
  }

  package static func hexadecimal(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var result: [UInt8] = []
    result.reserveCapacity(bytes.count * 2)
    for byte in bytes {
      result.append(digits[Int(byte >> 4)])
      result.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: result, as: UTF8.self)
  }

  package static func bytes(
    hexadecimal: String
  ) throws(DesignDatabaseRuntimeError) -> [UInt8] {
    let encoded = Array(hexadecimal.utf8)
    guard encoded.count.isMultiple(of: 2) else {
      throw .persistedStateCorrupt(reason: "A projection key has malformed hexadecimal encoding.")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(encoded.count / 2)
    var index = 0
    while index < encoded.count {
      guard let high = hexadecimalNibble(encoded[index]),
            let low = hexadecimalNibble(encoded[index + 1]) else {
        throw .persistedStateCorrupt(reason: "A projection key has malformed hexadecimal encoding.")
      }
      bytes.append((high << 4) | low)
      index += 2
    }
    return bytes
  }

  private static func hexadecimalNibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 97...102: byte - 87
    default: nil
    }
  }
}
