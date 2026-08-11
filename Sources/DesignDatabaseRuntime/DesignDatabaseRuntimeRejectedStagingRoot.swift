import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeRejectedStagingRoot {
  @discardableResult
  package static func validate(
    _ root: DesignStagingRootModel,
    intent: DesignCommitBuildIntentModel,
    databaseID: DesignDatabaseID,
    expectedState: DesignDatabaseRuntimeStagingRootState,
    using digester: any ContentDigesting
  ) throws(DesignDatabaseRuntimeError) -> DesignDatabaseOperationReference {
    let operation: DesignDatabaseOperationReference
    let requestDigest: ContentDigest
    let planDigest: ContentDigest
    let stagingDigest: ContentDigest
    do {
      operation = DesignDatabaseOperationReference(
        databaseID: try DesignDatabaseID(
          hexadecimalValue: intent.databaseID
        ),
        authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(
          hexadecimalValue: intent.subjectScopeID
        ),
        operationID: try DesignDatabaseOperationID(
          rawValue: intent.operationID
        )
      )
      requestDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: intent.requestDigestAlgorithm
        ),
        hexadecimalValue: intent.requestDigestValue
      )
      planDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: intent.planDigestAlgorithm
        ),
        hexadecimalValue: intent.planDigestValue
      )
      stagingDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(
          rawValue: intent.stagingDigestAlgorithm
        ),
        hexadecimalValue: intent.stagingDigestValue
      )
    } catch {
      throw .persistedStateCorrupt(
        reason: "A rejected staging root has a malformed commit binding."
      )
    }
    guard operation.databaseID == databaseID,
          root.id == intent.id,
          intent.id == DesignDatabaseRuntimeOperationClaim.key(operation),
          try DesignDatabaseRuntimeCommitBuildIntent.validateStatus(
            intent,
            operation: operation,
            requestDigest: requestDigest,
            using: digester
          ) == .rejected else {
      throw .persistedStateCorrupt(
        reason: "A rejected staging root does not bind a rejected commit."
      )
    }
    _ = try DesignDatabaseRuntimeStagingRoot.validateStatus(
      root,
      operation: operation,
      requestDigest: requestDigest,
      planDigest: planDigest,
      candidateRevisionID: intent.candidateRevisionID,
      stagingDigest: stagingDigest,
      expectedState: expectedState,
      using: digester
    )
    return operation
  }
}
