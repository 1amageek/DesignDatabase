import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeOperationClaim {
  package static let creationKind = "creation"
  package static let referenceKind = "reference"
  package static let retentionKind = "retention"
  package static let commitKind = "commit"
  package static let disjointMergeKind = "disjoint-merge"
  package static let commitAbandonmentKind = "commit-abandonment"
  package static let collectionKind = "collection"

  package static func make(
    operation: DesignDatabaseOperationReference,
    kind: String,
    requestDigest: ContentDigest
  ) -> DesignOperationClaimModel {
    var model = DesignOperationClaimModel()
    model.id = key(operation)
    model.databaseID = operation.databaseID.description
    model.subjectScopeID = operation.authorizationSubjectScopeID.description
    model.operationID = operation.operationID.rawValue
    model.operationKind = kind
    model.requestDigestAlgorithm = requestDigest.algorithm.rawValue
    model.requestDigestValue = requestDigest.hexadecimalValue
    return model
  }

  package static func matches(
    _ model: DesignOperationClaimModel,
    operation: DesignDatabaseOperationReference,
    kind: String,
    requestDigest: ContentDigest
  ) throws(DesignDatabaseRuntimeError) -> Bool {
    guard model.id == key(operation),
          model.databaseID == operation.databaseID.description,
          model.subjectScopeID == operation.authorizationSubjectScopeID.description,
          model.operationID == operation.operationID.rawValue else {
      throw .persistedStateCorrupt(
        reason: "An operation claim does not match its persisted scope."
      )
    }
    return model.operationKind == kind
      && model.requestDigestAlgorithm == requestDigest.algorithm.rawValue
      && model.requestDigestValue == requestDigest.hexadecimalValue
  }

  package static func key(
    _ operation: DesignDatabaseOperationReference
  ) -> String {
    operation.databaseID.description
      + ":" + operation.authorizationSubjectScopeID.description
      + ":" + operation.operationID.rawValue
  }
}
