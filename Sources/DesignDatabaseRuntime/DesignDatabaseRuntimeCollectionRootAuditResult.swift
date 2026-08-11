import CircuiteFoundation

package struct DesignDatabaseRuntimeCollectionRootAuditResult: Sendable {
  package let observedReachabilityGeneration: Int64
  package let rootSetDigest: ContentDigest
  package let reachableRevisionCount: UInt64
}
