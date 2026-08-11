import CircuiteFoundation
import Database
import DesignDatabaseCore

package enum DesignDatabaseRuntimeProjectionDirectory {
  package static func encode(
    _ materializations: [DesignProjectionTreeMaterialization]
  ) throws(DesignDatabaseRuntimeError) -> String {
    let ordered = materializations.sorted {
      $0.descriptor.family < $1.descriptor.family
    }
    for index in ordered.indices.dropFirst() where
      ordered[index - 1].descriptor.family == ordered[index].descriptor.family {
      throw .persistedStateCorrupt(
        reason: "A revision contains duplicate projection materializations."
      )
    }
    return ordered.map { materialization in
      materialization.descriptor.family.rawValue
        + "\t" + materialization.descriptorDigest.algorithm.rawValue
        + "\t" + materialization.descriptorDigest.hexadecimalValue
    }.joined(separator: "\n")
  }

  package static func load(
    revision: DesignRevisionReference,
    databaseID: DesignDatabaseID,
    count: Int64,
    encoded: String,
    transaction: DatabaseTransaction,
    digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) -> DesignProjectionRuntimeState {
    guard revision.databaseID == databaseID,
          let expectedCount = Int(exactly: count),
          expectedCount >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A revision projection directory has invalid identity or count."
      )
    }
    let lines = encoded.isEmpty
      ? []
      : encoded.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == expectedCount else {
      throw .persistedStateCorrupt(
        reason: "A revision projection directory has the wrong count."
      )
    }
    var references: [(DesignProjectionFamily, ContentDigest)] = []
    references.reserveCapacity(lines.count)
    for line in lines {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 3,
            let family = DesignProjectionFamily(rawValue: String(fields[0])) else {
        throw .persistedStateCorrupt(
          reason: "A revision projection directory entry is malformed."
        )
      }
      do {
        references.append((
          family,
          try ContentDigest(
            algorithm: ContentDigestAlgorithm(rawValue: String(fields[1])),
            hexadecimalValue: String(fields[2])
          )
        ))
      } catch {
        throw .persistedStateCorrupt(
          reason: "A revision projection descriptor digest is invalid."
        )
      }
    }
    guard references.map(\.0) == references.map(\.0).sorted(),
          Set(references.map(\.0)).count == references.count else {
      throw .persistedStateCorrupt(
        reason: "A revision projection directory is not canonical."
      )
    }

    do {
      var descriptors: [DesignProjectionSemanticDescriptor] = []
      var descriptorDigests: [DesignProjectionFamily: ContentDigest] = [:]
      var bindings: [DesignProjectionMaterializationBinding] = []
      var materializations: [
        DesignProjectionFamily: DesignProjectionRuntimeMaterialization
      ] = [:]
      for (family, expectedDescriptorDigest) in references {
        let id = revision.revisionID.description + ":" + family.rawValue
        guard let descriptorModel = try await transaction.fetch(
          DesignProjectionSemanticDescriptorModel.self,
          identifiedBy: id,
          consistency: .serializable
        ), let bindingModel = try await transaction.fetch(
          DesignProjectionBindingModel.self,
          identifiedBy: id,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A revision projection descriptor or binding is missing."
          )
        }
        let decodedDescriptor = try decodeDescriptor(
          descriptorModel,
          id: id,
          revision: revision,
          databaseID: databaseID,
          family: family,
          expectedDigest: expectedDescriptorDigest,
          digester: digester
        )
        let descriptor = decodedDescriptor.descriptor
        let reference = try decodeBinding(
          bindingModel,
          id: id,
          revision: revision,
          databaseID: databaseID,
          family: family,
          expectedDescriptorDigest: expectedDescriptorDigest
        )
        let materializationID = id + ":" + String(reference.bindingGeneration)
        guard let materialization = try await transaction.fetch(
          DesignProjectionMaterializationModel.self,
          identifiedBy: materializationID,
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A bound projection materialization is missing."
          )
        }
        let materializationSummary = try decodeMaterialization(
          materialization,
          id: materializationID,
          revision: revision,
          databaseID: databaseID,
          family: family,
          descriptor: descriptor,
          reference: reference
        )
        guard let root = try await transaction.fetch(
          DesignProjectionNodeModel.self,
          identifiedBy: DesignProjectionTreeMaterialization.digestKey(
            reference.rootNodeDigest
          ),
          consistency: .serializable
        ) else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A bound projection root node is missing."
          )
        }
        let rootNode = try DesignProjectionPersistedNodeDecoder.decode(
          root,
          expectedDigest: reference.rootNodeDigest,
          family: family,
          reference: reference,
          digester: digester
        )
        guard rootNode.level == materializationSummary.rootLevel,
              rootNode.subtreeEntryCount == descriptor.entryCount,
              rootNode.subtreeNodeCount
                == materializationSummary.totalNodeCount else {
          throw DesignDatabaseRuntimeError.persistedStateCorrupt(
            reason: "A projection root does not match its materialization summary."
          )
        }
        descriptors.append(descriptor)
        descriptorDigests[family] = expectedDescriptorDigest
        bindings.append(
          DesignProjectionMaterializationBinding(
            family: family,
            materialization: reference
          )
        )
        materializations[family] = DesignProjectionRuntimeMaterialization(
          descriptor: descriptor,
          descriptorDigest: expectedDescriptorDigest,
          semanticAccumulator: decodedDescriptor.accumulator,
          reference: reference,
          rootLevel: materializationSummary.rootLevel,
          totalNodeCount: materializationSummary.totalNodeCount
        )
      }
      return DesignProjectionRuntimeState(
        descriptors: descriptors,
        descriptorDigests: descriptorDigests,
        bindings: try DesignProjectionMaterializationBindingSet(bindings),
        materializations: materializations
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(
        reason: String(describing: error)
      )
    }
  }

  private static func decodeDescriptor(
    _ model: DesignProjectionSemanticDescriptorModel,
    id: String,
    revision: DesignRevisionReference,
    databaseID: DesignDatabaseID,
    family: DesignProjectionFamily,
    expectedDigest: ContentDigest,
    digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> (
    descriptor: DesignProjectionSemanticDescriptor,
    accumulator: DesignProjectionSemanticAccumulator
  ) {
    guard model.id == id,
          model.databaseID == databaseID.description,
          model.revisionID == revision.revisionID.description,
          model.family == family.rawValue,
          let major = UInt16(exactly: model.semanticVersionMajor),
          let minor = UInt16(exactly: model.semanticVersionMinor),
          major == 2,
          let entryCount = UInt64(model.entryCount),
          model.descriptorDigestAlgorithm == expectedDigest.algorithm.rawValue,
          model.descriptorDigestValue == expectedDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A projection semantic descriptor model is malformed."
      )
    }
    let minimumKey = try decodeOptionalKey(
      model.minimumKey,
      entryCount: entryCount
    )
    let maximumKey = try decodeOptionalKey(
      model.maximumKey,
      entryCount: entryCount
    )
    let firstAccumulator = try DesignProjectionTreeMaterialization.bytes(
      hexadecimal: model.accumulatorFirst
    )
    let secondAccumulator = try DesignProjectionTreeMaterialization.bytes(
      hexadecimal: model.accumulatorSecond
    )
    guard firstAccumulator.count == DesignProjectionSemanticAccumulator.byteCount,
          secondAccumulator.count == DesignProjectionSemanticAccumulator.byteCount else {
      throw .persistedStateCorrupt(
        reason: "A projection semantic accumulator is malformed."
      )
    }
    let accumulator = DesignProjectionSemanticAccumulator(
      first: firstAccumulator,
      second: secondAccumulator
    )
    let descriptor: DesignProjectionSemanticDescriptor
    do {
      descriptor = try DesignProjectionSemanticDescriptor(
        family: family,
        semanticVersion: DesignProjectionSemanticVersion(
          major: major,
          minor: minor
        ),
        entryCount: entryCount,
        minimumKey: minimumKey,
        maximumKey: maximumKey,
        canonicalSequenceDigest: try ContentDigest(
          algorithm: ContentDigestAlgorithm(
            rawValue: model.sequenceDigestAlgorithm
          ),
          hexadecimalValue: model.sequenceDigestValue
        )
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection semantic descriptor violates its contract."
      )
    }
    let actualDigest = try DesignProjectionTreeBuilder().semanticDescriptorDigest(
      descriptor,
      using: digester
    )
    let actualSequenceDigest = try accumulator.sequenceDigest(
      family: family,
      semanticVersion: descriptor.semanticVersion,
      entryCount: entryCount,
      using: digester
    )
    guard actualDigest == expectedDigest,
          actualSequenceDigest == descriptor.canonicalSequenceDigest else {
      throw .persistedStateCorrupt(
        reason: "A projection semantic descriptor digest does not match its payload."
      )
    }
    return (descriptor, accumulator)
  }

  private static func decodeBinding(
    _ model: DesignProjectionBindingModel,
    id: String,
    revision: DesignRevisionReference,
    databaseID: DesignDatabaseID,
    family: DesignProjectionFamily,
    expectedDescriptorDigest: ContentDigest
  ) throws(DesignDatabaseRuntimeError) -> DesignProjectionMaterializationReference {
    guard model.id == id,
          model.databaseID == databaseID.description,
          model.revisionID == revision.revisionID.description,
          model.family == family.rawValue,
          model.semanticDescriptorDigestAlgorithm == expectedDescriptorDigest.algorithm.rawValue,
          model.semanticDescriptorDigestValue == expectedDescriptorDigest.hexadecimalValue,
          let generation = UInt64(model.bindingGeneration),
          let codecMajor = UInt16(exactly: model.physicalCodecMajor),
          let codecMinor = UInt16(exactly: model.physicalCodecMinor) else {
      throw .persistedStateCorrupt(
        reason: "A projection materialization binding is malformed."
      )
    }
    do {
      return try DesignProjectionMaterializationReference(
        semanticDescriptorDigest: expectedDescriptorDigest,
        bindingGeneration: generation,
        physicalCodecVersion: DesignProjectionPhysicalCodecVersion(
          major: codecMajor,
          minor: codecMinor
        ),
        physicalProfileDigest: try ContentDigest(
          algorithm: ContentDigestAlgorithm(
            rawValue: model.physicalProfileDigestAlgorithm
          ),
          hexadecimalValue: model.physicalProfileDigestValue
        ),
        rootNodeDigest: try ContentDigest(
          algorithm: ContentDigestAlgorithm(
            rawValue: model.rootNodeDigestAlgorithm
          ),
          hexadecimalValue: model.rootNodeDigestValue
        )
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection materialization binding contains invalid digests."
      )
    }
  }

  private static func decodeMaterialization(
    _ model: DesignProjectionMaterializationModel,
    id: String,
    revision: DesignRevisionReference,
    databaseID: DesignDatabaseID,
    family: DesignProjectionFamily,
    descriptor: DesignProjectionSemanticDescriptor,
    reference: DesignProjectionMaterializationReference
  ) throws(DesignDatabaseRuntimeError) -> (
    rootLevel: UInt16,
    totalNodeCount: UInt64
  ) {
    guard model.id == id,
          model.databaseID == databaseID.description,
          model.revisionID == revision.revisionID.description,
          model.family == family.rawValue,
          model.semanticDescriptorDigestAlgorithm == reference.semanticDescriptorDigest.algorithm.rawValue,
          model.semanticDescriptorDigestValue == reference.semanticDescriptorDigest.hexadecimalValue,
          model.bindingGeneration == String(reference.bindingGeneration),
          model.physicalCodecMajor == Int64(reference.physicalCodecVersion.major),
          model.physicalCodecMinor == Int64(reference.physicalCodecVersion.minor),
          model.physicalProfileDigestAlgorithm == reference.physicalProfileDigest.algorithm.rawValue,
          model.physicalProfileDigestValue == reference.physicalProfileDigest.hexadecimalValue,
          model.rootNodeDigestAlgorithm == reference.rootNodeDigest.algorithm.rawValue,
          model.rootNodeDigestValue == reference.rootNodeDigest.hexadecimalValue,
          let treeHeight = UInt16(exactly: model.treeHeight),
          treeHeight > 0,
          let totalNodeCount = UInt64(model.nodeCount),
          totalNodeCount > 0,
          UInt64(treeHeight) <= totalNodeCount,
          model.entryCount == String(descriptor.entryCount),
          model.verificationState == 1 else {
      throw .persistedStateCorrupt(
        reason: "A projection materialization record is incomplete or inconsistent."
      )
    }
    return (treeHeight - 1, totalNodeCount)
  }

  private static func decodeOptionalKey(
    _ value: String,
    entryCount: UInt64
  ) throws(DesignDatabaseRuntimeError) -> DesignCanonicalKey? {
    if entryCount == 0 {
      guard value.isEmpty else {
        throw .persistedStateCorrupt(
          reason: "An empty projection descriptor declares a key bound."
        )
      }
      return nil
    }
    guard !value.isEmpty else {
      throw .persistedStateCorrupt(
        reason: "A non-empty projection descriptor omits a key bound."
      )
    }
    do {
      return try DesignCanonicalKey(
        bytes: DesignProjectionTreeMaterialization.bytes(hexadecimal: value)
      )
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection descriptor key bound is invalid."
      )
    }
  }
}
