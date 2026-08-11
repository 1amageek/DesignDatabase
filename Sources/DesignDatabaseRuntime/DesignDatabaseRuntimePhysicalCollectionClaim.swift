import CircuiteFoundation
import Database

package enum DesignDatabaseRuntimePhysicalCollectionClaimState:
  Int64,
  Sendable
{
  case claimed = 0
  case deleted = 1
}

package enum DesignDatabaseRuntimePhysicalCollectionClaim {
  package static let projectionNodeStorageType =
    "DesignDatabaseRuntime.DesignProjectionNode.v2"
  package static let projectionDescriptorStorageType =
    "DesignDatabaseRuntime.DesignProjectionSemanticDescriptor.v2"
  package static let projectionBindingStorageType =
    "DesignDatabaseRuntime.DesignProjectionBinding.v2"
  package static let projectionMaterializationStorageType =
    "DesignDatabaseRuntime.DesignProjectionMaterialization.v2"

  package static func projectionNodeIdentity(
    _ model: DesignProjectionNodeModel
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    do {
      return try DesignDatabaseRuntimeImmutableWriteIdentity(
        storageType: projectionNodeStorageType,
        partitionComponents: [
          model.family,
          String(model.physicalCodecMajor) + "." + String(model.physicalCodecMinor),
          model.physicalProfileDigestAlgorithm
            + ":" + model.physicalProfileDigestValue,
        ],
        modelID: model.id
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection node could not form a physical write identity."
      )
    }
  }

  package static func projectionDescriptorIdentity(
    _ model: DesignProjectionSemanticDescriptorModel
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    try projectionMetadataIdentity(
      storageType: projectionDescriptorStorageType,
      databaseID: model.databaseID,
      revisionID: model.revisionID,
      family: model.family,
      modelID: model.id
    )
  }

  package static func projectionBindingIdentity(
    _ model: DesignProjectionBindingModel
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    try projectionMetadataIdentity(
      storageType: projectionBindingStorageType,
      databaseID: model.databaseID,
      revisionID: model.revisionID,
      family: model.family,
      modelID: model.id
    )
  }

  package static func projectionMaterializationIdentity(
    _ model: DesignProjectionMaterializationModel
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    try projectionMetadataIdentity(
      storageType: projectionMaterializationStorageType,
      databaseID: model.databaseID,
      revisionID: model.revisionID,
      family: model.family,
      modelID: model.id
    )
  }

  package static func makeClaimed(
    identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    collectionIntentID: String,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignPhysicalCollectionClaimModel {
    guard !collectionIntentID.isEmpty else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim has an empty intent identity."
      )
    }
    let identityDigest = try digest(identity, using: digester)
    var model = DesignPhysicalCollectionClaimModel()
    model.id = key(identityDigest)
    model.collectionIntentID = collectionIntentID
    model.canonicalIdentity = ByteString(identity.canonicalBytes)
    model.identityDigestAlgorithm = identityDigest.algorithm.rawValue
    model.identityDigestValue = identityDigest.hexadecimalValue
    model.state = DesignDatabaseRuntimePhysicalCollectionClaimState.claimed.rawValue
    return try updatingStateDigest(model, using: digester)
  }

  package static func requireUnclaimed(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    transaction: any DatabaseTransactionReading,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError) {
    let identityDigest = try digest(identity, using: digester)
    let claim: DesignPhysicalCollectionClaimModel?
    do {
      claim = try await transaction.fetch(
        DesignPhysicalCollectionClaimModel.self,
        identifiedBy: key(identityDigest)
      )
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard let claim else {
      return
    }
    let state = try validate(
      claim,
      expectedIdentity: identity,
      using: digester
    )
    if state == .claimed {
      throw .physicalWriteDeleting(
        identity: claim.id,
        collectionOperation: claim.collectionIntentID
      )
    }
  }

  package static func transitionedDeleted(
    _ model: DesignPhysicalCollectionClaimModel,
    expectedIdentity: DesignDatabaseRuntimeImmutableWriteIdentity,
    collectionIntentID: String,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignPhysicalCollectionClaimModel {
    let state = try validate(
      model,
      expectedIdentity: expectedIdentity,
      using: digester
    )
    guard state == .claimed,
          model.collectionIntentID == collectionIntentID else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim cannot transition to deleted."
      )
    }
    var updated = model
    updated.state = DesignDatabaseRuntimePhysicalCollectionClaimState
      .deleted.rawValue
    return try updatingStateDigest(updated, using: digester)
  }

  package static func isRuntimeManagedStorageType(
    _ storageType: String
  ) -> Bool {
    switch storageType {
    case projectionNodeStorageType,
         projectionDescriptorStorageType,
         projectionBindingStorageType,
         projectionMaterializationStorageType:
      return true
    default:
      return false
    }
  }

  package static func key(
    for identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> String {
    key(try digest(identity, using: digester))
  }

  package static func identitySetDigest(
    _ identities: [DesignDatabaseRuntimeImmutableWriteIdentity],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    let ordered = identities.sorted()
    guard ordered == identities,
          Set(ordered).count == ordered.count,
          let count = UInt64(exactly: ordered.count) else {
      throw .persistedStateCorrupt(
        reason: "A physical collection identity set is not canonical."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.PhysicalCollectionIdentitySet"
    )
    encoder.append(count)
    for identity in ordered {
      encoder.append(identity.canonicalBytes)
    }
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A physical collection identity set digest could not be computed: \(error)"
      )
    }
  }

  @discardableResult
  package static func validate(
    _ model: DesignPhysicalCollectionClaimModel,
    expectedIdentity: DesignDatabaseRuntimeImmutableWriteIdentity? = nil,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimePhysicalCollectionClaimState
  {
    let canonicalBytes = Array(model.canonicalIdentity)
    guard !model.collectionIntentID.isEmpty,
          !canonicalBytes.isEmpty,
          let state = DesignDatabaseRuntimePhysicalCollectionClaimState(
            rawValue: model.state
          ) else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim has malformed identity or state."
      )
    }
    let identityDigest = try digest(canonicalBytes, using: digester)
    guard model.id == key(identityDigest),
          model.identityDigestAlgorithm == identityDigest.algorithm.rawValue,
          model.identityDigestValue == identityDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim identity digest is invalid."
      )
    }
    if let expectedIdentity,
       expectedIdentity.canonicalBytes != canonicalBytes {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim digest collided with another identity."
      )
    }
    let expectedStateDigest = try stateDigest(model, using: digester)
    guard model.stateDigestAlgorithm == expectedStateDigest.algorithm.rawValue,
          model.stateDigestValue == expectedStateDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim state digest is invalid."
      )
    }
    return state
  }

  private static func digest(
    _ identity: DesignDatabaseRuntimeImmutableWriteIdentity,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    try digest(identity.canonicalBytes, using: digester)
  }

  private static func projectionMetadataIdentity(
    storageType: String,
    databaseID: String,
    revisionID: String,
    family: String,
    modelID: String
  ) throws(DesignDatabaseRuntimeError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity
  {
    do {
      return try DesignDatabaseRuntimeImmutableWriteIdentity(
        storageType: storageType,
        partitionComponents: [databaseID, revisionID, family],
        modelID: modelID
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A projection metadata model could not form a physical write identity."
      )
    }
  }

  private static func digest(
    _ bytes: [UInt8],
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.ImmutablePhysicalWrite"
    )
    encoder.append(bytes)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A physical write identity digest could not be computed: \(error)"
      )
    }
  }

  private static func key(_ digest: ContentDigest) -> String {
    digest.algorithm.rawValue + ":" + digest.hexadecimalValue
  }

  private static func updatingStateDigest(
    _ model: DesignPhysicalCollectionClaimModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignPhysicalCollectionClaimModel {
    var updated = model
    let digest = try stateDigest(updated, using: digester)
    updated.stateDigestAlgorithm = digest.algorithm.rawValue
    updated.stateDigestValue = digest.hexadecimalValue
    return updated
  }

  private static func stateDigest(
    _ model: DesignPhysicalCollectionClaimModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard let state = UInt64(exactly: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A physical collection claim has a negative state."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.PhysicalCollectionClaim"
    )
    encoder.append(model.id)
    encoder.append(model.collectionIntentID)
    encoder.append(Array(model.canonicalIdentity))
    encoder.append(model.identityDigestAlgorithm)
    encoder.append(model.identityDigestValue)
    encoder.append(state)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "A physical collection claim state digest could not be computed: \(error)"
      )
    }
  }
}
