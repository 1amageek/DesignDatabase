import CircuiteFoundation
import DesignDatabaseCore

package enum DesignProjectionRelationChangeValidator {
  private struct Key: Hashable {
    let family: DesignProjectionFamily
    let occurrenceID: DesignRelationOccurrenceID
  }

  private struct Side {
    var record: DesignRelationOccurrenceRecord?
    var entries: Set<DesignProjectionEntry> = []
  }

  private struct Contribution {
    let segmentID: DesignMutationPlanSegmentID
    var before = Side()
    var after = Side()
  }

  package static func validate(
    mutations: [DesignDatabaseRuntimeCandidateProjectionPlan.MutationChanges],
    identityAssignments: [
      DesignMutationPlanSegmentID: DesignMutationIdentityAssignments
    ]
  ) -> DesignCommitRejection.Reason? {
    var contributions: [Key: Contribution] = [:]
    for mutation in mutations {
      for change in mutation.changes where relationalFamilies.contains(change.family) {
        let beforeRecord: DesignRelationOccurrenceRecord?
        let afterRecord: DesignRelationOccurrenceRecord?
        do {
          beforeRecord = try change.before.map(
            DesignRelationOccurrenceRecord.init(projectionEntry:)
          )
          afterRecord = try change.after.map(
            DesignRelationOccurrenceRecord.init(projectionEntry:)
          )
        } catch {
          return invalidSegment(
            mutation.segmentID,
            "A relation projection change is not a canonical occurrence record."
          )
        }
        guard beforeRecord?.projectionFamily == change.family || beforeRecord == nil,
              afterRecord?.projectionFamily == change.family || afterRecord == nil else {
          return invalidSegment(
            mutation.segmentID,
            "A relation projection record does not match its declared family."
          )
        }
        if let beforeRecord, let afterRecord,
           beforeRecord.occurrenceID != afterRecord.occurrenceID {
          return invalidSegment(
            mutation.segmentID,
            "A relation projection change cannot replace one occurrence identity with another."
          )
        }
        guard let occurrenceID = beforeRecord?.occurrenceID
          ?? afterRecord?.occurrenceID else {
          return invalidSegment(
            mutation.segmentID,
            "A relation projection change contains no occurrence record."
          )
        }
        let key = Key(family: change.family, occurrenceID: occurrenceID)
        var contribution = contributions[key] ?? Contribution(
          segmentID: mutation.segmentID
        )
        guard contribution.segmentID == mutation.segmentID else {
          return invalidSegment(
            mutation.segmentID,
            "One relation occurrence cannot be changed by multiple plan segments."
          )
        }
        if let beforeRecord, let beforeEntry = change.before {
          if let existing = contribution.before.record,
             existing != beforeRecord {
            return invalidSegment(
              mutation.segmentID,
              "A relation occurrence has inconsistent before records."
            )
          }
          guard contribution.before.entries.insert(beforeEntry).inserted else {
            return invalidSegment(
              mutation.segmentID,
              "A relation occurrence contains a duplicate before entry."
            )
          }
          contribution.before.record = beforeRecord
        }
        if let afterRecord, let afterEntry = change.after {
          if let existing = contribution.after.record,
             existing != afterRecord {
            return invalidSegment(
              mutation.segmentID,
              "A relation occurrence has inconsistent after records."
            )
          }
          guard contribution.after.entries.insert(afterEntry).inserted else {
            return invalidSegment(
              mutation.segmentID,
              "A relation occurrence contains a duplicate after entry."
            )
          }
          contribution.after.record = afterRecord
        }
        contributions[key] = contribution
      }
    }

    for contribution in contributions.values {
      if let rejection = validateSide(
        contribution.before,
        name: "before",
        segmentID: contribution.segmentID
      ) {
        return rejection
      }
      if let rejection = validateSide(
        contribution.after,
        name: "after",
        segmentID: contribution.segmentID
      ) {
        return rejection
      }
      if contribution.before.record == nil,
         let inserted = contribution.after.record {
        guard identityAssignments[contribution.segmentID]?
          .relationOccurrences.contains(where: {
            $0.permanentID == inserted.occurrenceID
          }) == true else {
          return invalidSegment(
            contribution.segmentID,
            "An inserted relation occurrence does not use an identity reserved for its segment."
          )
        }
      }
    }
    return nil
  }

  private static func validateSide(
    _ side: Side,
    name: String,
    segmentID: DesignMutationPlanSegmentID
  ) -> DesignCommitRejection.Reason? {
    guard let record = side.record else {
      guard side.entries.isEmpty else {
        return invalidSegment(
          segmentID,
          "A relation occurrence has entries without a \(name) record."
        )
      }
      return nil
    }
    let expected: Set<DesignProjectionEntry>
    do {
      expected = Set(try record.projectionEntries())
    } catch {
      return invalidSegment(
        segmentID,
        "A relation-occurrence \(name) record could not be canonicalized."
      )
    }
    guard side.entries == expected else {
      return invalidSegment(
        segmentID,
        "A relation occurrence must contribute its exact \(name) outgoing and incoming entries."
      )
    }
    return nil
  }

  private static func invalidSegment(
    _ segmentID: DesignMutationPlanSegmentID,
    _ reason: String
  ) -> DesignCommitRejection.Reason {
    .invalidSegmentPayload(segmentID: segmentID, reason: reason)
  }

  private static let relationalFamilies: Set<DesignProjectionFamily> = [
    .hierarchy,
    .connectivity,
    .crossFacet,
    .dependency,
  ]
}
