import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeCollectionSweepProgress: Sendable {
  package let operation: DesignDatabaseOperationReference
  package let requestDigest: ContentDigest
  package let deletedPhysicalIdentityCount: UInt64
  package let physicalIdentityCount: UInt64
  package let intentStateDigest: ContentDigest
}

package struct DesignDatabaseRuntimeCollectionReceipt: Sendable {
  package let operation: DesignDatabaseOperationReference
  package let requestDigest: ContentDigest
  package let candidates: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  package let originalRootSetDigest: ContentDigest
  package let physicalRootSetDigest: ContentDigest
  package let physicalIdentityDirectoryDigest: ContentDigest
  package let physicalIdentityCount: UInt64
  package let rejectedStagingRootIDs: [String]
  package let admittedReachabilityGeneration: Int64
  package let completedReachabilityGeneration: Int64
  package let intentStateDigest: ContentDigest
}

package enum DesignDatabaseRuntimeCollectionSweepResult: Sendable {
  case sweeping(DesignDatabaseRuntimeCollectionSweepProgress)
  case collected(DesignDatabaseRuntimeCollectionReceipt)
  case outcomeUnknown(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  )
}
