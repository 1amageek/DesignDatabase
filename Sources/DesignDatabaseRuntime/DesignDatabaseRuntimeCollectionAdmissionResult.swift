import CircuiteFoundation
import DesignDatabaseCore

package enum DesignDatabaseRuntimeCollectionAdmissionResult: Sendable {
  case admitted(DesignCollectionIntentModel)
  case collected(DesignCollectionIntentModel)
  case outcomeUnknown(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  )
}
