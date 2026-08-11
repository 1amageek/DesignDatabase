import CircuiteFoundation

package struct DesignDatabaseRuntimeCollectionPhysicalRootAuditResult: Sendable {
  package let observedReachabilityGeneration: Int64
  package let rootSetDigest: ContentDigest
  package let claimSetDigest: ContentDigest
  package let claimedIdentities: [DesignDatabaseRuntimeImmutableWriteIdentity]
  package let rejectedStagingRootIDs: [String]
  package let protectedIdentityCount: UInt64
}
