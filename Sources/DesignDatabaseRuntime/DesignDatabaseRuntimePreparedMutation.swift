import CircuiteFoundation
import Database
import DesignDatabaseCore

public protocol DesignDatabaseRuntimePreparedMutation: Sendable {
  var segmentID: DesignMutationPlanSegmentID { get }
  var writeCount: UInt64 { get }
  /// Canonical root of the complete target facet after applying this segment.
  var facetRootDigest: ContentDigest { get }
  var changeContributionDigest: ContentDigest { get }
  var projectionChanges: [DesignProjectionChange] { get }

  /// Returns the stable Runtime-local physical identity of one immutable
  /// write. The identity is used only for collection fencing and must not be
  /// mixed into semantic revision, artifact, or release identity.
  func immutableWriteIdentity(
    at index: UInt64
  ) throws(DesignDatabaseRuntimePreparedMutationError)
    -> DesignDatabaseRuntimeImmutableWriteIdentity

  /// Stages one already validated immutable model. Implementations must reject
  /// an index outside `0..<writeCount`, must not expose canonical revision
  /// state, and must be deterministic and idempotent when the framework retries
  /// the surrounding transaction.
  func stageImmutableWrite(
    at index: UInt64,
    to transaction: any DatabaseTransactionWriting
  ) async throws
}

public extension DesignDatabaseRuntimePreparedMutation {
  var projectionChanges: [DesignProjectionChange] { [] }
}
