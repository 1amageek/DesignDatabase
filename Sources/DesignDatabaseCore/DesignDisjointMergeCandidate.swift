import CircuiteFoundation

public struct DesignDisjointMergeCandidate: Sendable, Hashable, DesignDatabaseSerializable {
  public let baseRevision: DesignRevisionReference
  public let parentRevisions: [DesignRevisionReference]
  public let designSchemaBundleDigest: ContentDigest
  public let dependencyRootDigest: ContentDigest
  public let semanticDependencyGraphDigest: ContentDigest
  public let facetRoots: [DesignFacetRoot]
  public let leftChangedFacetIDs: [DesignFacetID]
  public let rightChangedFacetIDs: [DesignFacetID]
  public let semanticValidationRequirements:
    [DesignDisjointMergeSemanticValidationRequirement]
  public let resourceReport: DesignDisjointMergeResourceReport

  public init(
    baseRevision: DesignRevisionReference,
    parentRevisions: [DesignRevisionReference],
    designSchemaBundleDigest: ContentDigest,
    dependencyRootDigest: ContentDigest,
    semanticDependencyGraphDigest: ContentDigest,
    facetRoots: [DesignFacetRoot],
    leftChangedFacetIDs: [DesignFacetID],
    rightChangedFacetIDs: [DesignFacetID],
    semanticValidationRequirements:
      [DesignDisjointMergeSemanticValidationRequirement],
    resourceReport: DesignDisjointMergeResourceReport
  ) throws(DesignDatabaseError) {
    guard parentRevisions.count == 2,
          Set(parentRevisions).count == 2,
          parentRevisions.allSatisfy({
            $0.databaseID == baseRevision.databaseID
          }) else {
      throw .invalidMergeRequest(
        reason: "A disjoint merge candidate requires two distinct same-database parents."
      )
    }
    self.baseRevision = baseRevision
    let firstParentPrecedesSecond = parentRevisions[0].revisionID.description
      < parentRevisions[1].revisionID.description
    self.parentRevisions = parentRevisions.sorted {
      $0.revisionID.description < $1.revisionID.description
    }
    self.designSchemaBundleDigest = designSchemaBundleDigest
    self.dependencyRootDigest = dependencyRootDigest
    self.semanticDependencyGraphDigest = semanticDependencyGraphDigest
    self.facetRoots = try DesignFacetRoot.canonicalizing(facetRoots)
    let canonicalFirstChangedFacetIDs = firstParentPrecedesSecond
      ? leftChangedFacetIDs
      : rightChangedFacetIDs
    let canonicalSecondChangedFacetIDs = firstParentPrecedesSecond
      ? rightChangedFacetIDs
      : leftChangedFacetIDs
    self.leftChangedFacetIDs = canonicalFirstChangedFacetIDs.sorted {
      $0.rawValue < $1.rawValue
    }
    self.rightChangedFacetIDs = canonicalSecondChangedFacetIDs.sorted {
      $0.rawValue < $1.rawValue
    }
    self.semanticValidationRequirements = semanticValidationRequirements
    self.resourceReport = resourceReport
  }

#if DESIGN_DATABASE_FOUNDATION_SERIALIZATION
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        baseRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .baseRevision
        ),
        parentRevisions: container.decode(
          [DesignRevisionReference].self,
          forKey: .parentRevisions
        ),
        designSchemaBundleDigest: container.decode(
          ContentDigest.self,
          forKey: .designSchemaBundleDigest
        ),
        dependencyRootDigest: container.decode(
          ContentDigest.self,
          forKey: .dependencyRootDigest
        ),
        semanticDependencyGraphDigest: container.decode(
          ContentDigest.self,
          forKey: .semanticDependencyGraphDigest
        ),
        facetRoots: container.decode(
          [DesignFacetRoot].self,
          forKey: .facetRoots
        ),
        leftChangedFacetIDs: container.decode(
          [DesignFacetID].self,
          forKey: .leftChangedFacetIDs
        ),
        rightChangedFacetIDs: container.decode(
          [DesignFacetID].self,
          forKey: .rightChangedFacetIDs
        ),
        semanticValidationRequirements: container.decode(
          [DesignDisjointMergeSemanticValidationRequirement].self,
          forKey: .semanticValidationRequirements
        ),
        resourceReport: container.decode(
          DesignDisjointMergeResourceReport.self,
          forKey: .resourceReport
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
#endif
}
