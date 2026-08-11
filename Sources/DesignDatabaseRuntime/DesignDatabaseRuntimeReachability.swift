import CircuiteFoundation
import Database

package enum DesignDatabaseRuntimeReachability {
  package static func require(
    databaseID: DesignDatabaseID,
    transaction: DatabaseTransaction
  ) async throws(DesignDatabaseRuntimeError) -> DesignReachabilityStateModel {
    do {
      guard let state = try await transaction.fetch(
        DesignReachabilityStateModel.self,
        identifiedBy: "active",
        consistency: .serializable
      ), state.databaseID == databaseID.description,
         state.generation >= 0 else {
        throw DesignDatabaseRuntimeError.persistedStateCorrupt(
          reason: "The reachability generation state is missing or invalid."
        )
      }
      return state
    } catch let error as DesignDatabaseRuntimeError {
      throw error
    } catch {
      throw .commitTransactionFailed(reason: String(describing: error))
    }
  }

  package static func advanced(
    _ state: DesignReachabilityStateModel,
    kind: String
  ) throws(DesignDatabaseRuntimeError) -> DesignReachabilityStateModel {
    guard state.generation >= 0, state.generation < Int64.max else {
      throw .generationExhausted(kind: kind)
    }
    var updated = state
    updated.generation += 1
    return updated
  }
}
