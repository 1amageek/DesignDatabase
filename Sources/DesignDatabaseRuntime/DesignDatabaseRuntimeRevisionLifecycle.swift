import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeRevisionLifecycleState: Int64, Sendable {
  case visible = 0
  case deleting = 1
  case collected = 2
}

package enum DesignDatabaseRuntimeRevisionLifecycle {
  package static func makeVisible(
    revision: DesignRevisionReference,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionLifecycleModel {
    guard reachabilityGeneration >= 0 else {
      throw .persistedStateCorrupt(
        reason: "A visible revision lifecycle has a negative generation."
      )
    }
    var model = DesignRevisionLifecycleModel()
    model.id = revision.revisionID.description
    model.databaseID = revision.databaseID.description
    model.revisionID = revision.revisionID.description
    model.state = DesignDatabaseRuntimeRevisionLifecycleState.visible.rawValue
    model.reachabilityGeneration = reachabilityGeneration
    return try updatingStateDigest(model, using: digester)
  }

  package static func transitioned(
    _ model: DesignRevisionLifecycleModel,
    revision: DesignRevisionReference,
    from expectedState: DesignDatabaseRuntimeRevisionLifecycleState,
    to newState: DesignDatabaseRuntimeRevisionLifecycleState,
    reachabilityGeneration: Int64,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionLifecycleModel {
    let currentState = try validate(
      model,
      revision: revision,
      using: digester
    )
    guard currentState == expectedState,
          (expectedState == .visible && newState == .deleting)
            || (expectedState == .deleting && newState == .collected),
          reachabilityGeneration > model.reachabilityGeneration else {
      throw .persistedStateCorrupt(
        reason: "A revision lifecycle transition is invalid."
      )
    }
    var updated = model
    updated.state = newState.rawValue
    updated.reachabilityGeneration = reachabilityGeneration
    return try updatingStateDigest(updated, using: digester)
  }

  @discardableResult
  package static func requireVisible(
    _ model: DesignRevisionLifecycleModel?,
    revision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeRevisionLifecycleState {
    guard let model else {
      throw .persistedStateCorrupt(
        reason: "A revision manifest has no lifecycle record."
      )
    }
    let state = try validate(model, revision: revision, using: digester)
    switch state {
    case .visible:
      return state
    case .deleting:
      throw .revisionDeleting(revision.revisionID.description)
    case .collected:
      throw .revisionCollected(revision.revisionID.description)
    }
  }

  @discardableResult
  package static func validate(
    _ model: DesignRevisionLifecycleModel,
    revision: DesignRevisionReference,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseRuntimeRevisionLifecycleState {
    guard model.id == revision.revisionID.description,
          model.databaseID == revision.databaseID.description,
          model.revisionID == revision.revisionID.description,
          model.reachabilityGeneration >= 0,
          let state = DesignDatabaseRuntimeRevisionLifecycleState(
            rawValue: model.state
          ) else {
      throw .persistedStateCorrupt(
        reason: "A revision lifecycle record is malformed."
      )
    }
    let expectedDigest = try stateDigest(model, using: digester)
    guard model.stateDigestAlgorithm == expectedDigest.algorithm.rawValue,
          model.stateDigestValue == expectedDigest.hexadecimalValue else {
      throw .persistedStateCorrupt(
        reason: "A revision lifecycle state digest is invalid."
      )
    }
    return state
  }

  private static func updatingStateDigest(
    _ model: DesignRevisionLifecycleModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignRevisionLifecycleModel {
    var updated = model
    let digest = try stateDigest(updated, using: digester)
    updated.stateDigestAlgorithm = digest.algorithm.rawValue
    updated.stateDigestValue = digest.hexadecimalValue
    return updated
  }

  private static func stateDigest(
    _ model: DesignRevisionLifecycleModel,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> ContentDigest {
    guard let generation = UInt64(exactly: model.reachabilityGeneration),
          let state = UInt64(exactly: model.state) else {
      throw .persistedStateCorrupt(
        reason: "A revision lifecycle has a negative generation or state."
      )
    }
    var encoder = DesignDatabaseRuntimeDigestEncoder(
      domain: "DesignDatabase.RevisionLifecycle"
    )
    encoder.append(model.id)
    encoder.append(model.databaseID)
    encoder.append(model.revisionID)
    encoder.append(state)
    encoder.append(generation)
    do {
      return try encoder.finalize(using: digester)
    } catch {
      throw .commitTransactionFailed(
        reason: "The revision lifecycle digest could not be computed: \(error)"
      )
    }
  }
}
