import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimeMutationRestoration: Sendable {
  public let databaseID: DesignDatabaseID
  public let baseRevision: DesignRevisionReference
  public let candidateRevision: DesignRevisionReference
  public let designSchemaBundleDigest: ContentDigest
  public let directDependencyLock: DesignDependencyLock
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let baseFacetRoots: [DesignFacetRoot]

  private let identityAssignmentsBySegment: [
    DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
  ]

  package init(
    databaseID: DesignDatabaseID,
    baseRevision: DesignRevisionReference,
    candidateRevision: DesignRevisionReference,
    designSchemaBundleDigest: ContentDigest,
    directDependencyLock: DesignDependencyLock,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    baseFacetRoots: [DesignFacetRoot],
    identityAssignmentsBySegment: [
      DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
    ]
  ) {
    self.databaseID = databaseID
    self.baseRevision = baseRevision
    self.candidateRevision = candidateRevision
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.directDependencyLock = directDependencyLock
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.baseFacetRoots = baseFacetRoots
    self.identityAssignmentsBySegment = identityAssignmentsBySegment
  }

  public func identityAssignments(
    for segmentID: DesignMutationPlanSegmentID
  ) -> DesignMutationIdentityAssignments? {
    identityAssignmentsBySegment[segmentID]
  }
}
