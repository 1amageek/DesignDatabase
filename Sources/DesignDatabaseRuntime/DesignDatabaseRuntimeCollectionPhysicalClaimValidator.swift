import CircuiteFoundation
import Database

package enum DesignDatabaseRuntimeCollectionPhysicalClaimValidator {
  package static func validate(
    directory: DesignDatabaseRuntimeCollectionPhysicalIdentityDirectory,
    collectionIntentID: String,
    context: DatabaseContext,
    using digester: any ContentDigesting
  ) async throws(DesignDatabaseRuntimeError)
    -> [DesignDatabaseRuntimePhysicalCollectionClaimState]
  {
    guard !directory.identities.isEmpty else { return [] }
    var keys: [String] = []
    keys.reserveCapacity(directory.identities.count)
    for identity in directory.identities {
      keys.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim.key(
          for: identity,
          using: digester
        )
      )
    }
    let claimKeys = keys
    let claims: [DesignPhysicalCollectionClaimModel]
    do {
      claims = try await context.withTransaction { transaction in
        try await transaction.fetch(
          DesignPhysicalCollectionClaimModel.self,
          identifiedBy: claimKeys,
          consistency: .serializable
        )
      }
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
    guard claims.count == directory.identities.count else {
      throw .persistedStateCorrupt(
        reason: "A collection physical identity directory has missing claims."
      )
    }
    let claimByID = Dictionary(uniqueKeysWithValues: claims.map { ($0.id, $0) })
    guard claimByID.count == claims.count else {
      throw .persistedStateCorrupt(
        reason: "A collection physical claim set contains duplicate identities."
      )
    }
    var states: [DesignDatabaseRuntimePhysicalCollectionClaimState] = []
    states.reserveCapacity(directory.identities.count)
    for (identity, key) in zip(directory.identities, claimKeys) {
      guard let claim = claimByID[key],
            claim.collectionIntentID == collectionIntentID else {
        throw .persistedStateCorrupt(
          reason: "A physical collection claim has the wrong owning operation."
        )
      }
      states.append(
        try DesignDatabaseRuntimePhysicalCollectionClaim.validate(
          claim,
          expectedIdentity: identity,
          using: digester
        )
      )
    }
    return states
  }
}
