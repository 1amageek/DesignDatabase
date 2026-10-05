import CircuiteFoundation

public protocol DesignDatabaseMaintenanceHandle: Sendable {
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }

  func collectRevisions(
    _ request: DesignRevisionCollectionRequest,
    budget: DesignRevisionCollectionBudget
  ) async throws(DesignDatabaseError) -> DesignRevisionCollectionStatus

  func revisionCollectionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest,
    budget: DesignRevisionCollectionBudget
  ) async throws(DesignDatabaseError) -> DesignRevisionCollectionStatus

  func abandonCommit(
    _ request: DesignCommitAbandonmentRequest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentResult

  func commitAbandonmentStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentStatus
}

public extension DesignDatabaseMaintenanceHandle {
  func collectRevisions(_ request: DesignRevisionCollectionRequest, budget: DesignRevisionCollectionBudget) async throws(DesignDatabaseError) -> DesignRevisionCollectionStatus {
    do {
      let capability = try DesignCapabilityID(rawValue: "design-database.revision-collection")
      throw DesignDatabaseError.unsupportedCapability(capability)
    } catch let error as DesignDatabaseError { throw error }
    catch { throw .corruption("The revision collection capability identifier is invalid.") }
  }
  func revisionCollectionStatus(operation: DesignDatabaseOperationReference, requestDigest: ContentDigest, budget: DesignRevisionCollectionBudget) async throws(DesignDatabaseError) -> DesignRevisionCollectionStatus {
    do {
      let capability = try DesignCapabilityID(rawValue: "design-database.revision-collection")
      throw DesignDatabaseError.unsupportedCapability(capability)
    } catch let error as DesignDatabaseError { throw error }
    catch { throw .corruption("The revision collection capability identifier is invalid.") }
  }
}
