import CircuiteFoundation
import DesignDatabaseCore

package struct DesignDatabaseRuntimeRevisionDeletionCandidateSet:
  Sendable,
  Hashable
{
  package let databaseID: DesignDatabaseID
  package let revisions: [DesignRevisionReference]

  package init(
    revisions: [DesignRevisionReference],
    maximumRevisionCount: UInt64 = 256
  ) throws(DesignDatabaseRuntimeError) {
    guard !revisions.isEmpty else {
      throw .persistedStateCorrupt(
        reason: "A revision deletion candidate set is empty."
      )
    }
    guard let requestedCount = UInt64(exactly: revisions.count),
          requestedCount <= maximumRevisionCount else {
      throw .deletionCandidateBudgetExceeded(
        limit: maximumRevisionCount,
        requested: UInt64(exactly: revisions.count) ?? UInt64.max
      )
    }
    let databaseID = revisions[0].databaseID
    guard revisions.allSatisfy({ $0.databaseID == databaseID }) else {
      throw .persistedStateCorrupt(
        reason: "A revision deletion candidate set crosses a database boundary."
      )
    }
    let ordered = revisions.sorted {
      $0.revisionID.description < $1.revisionID.description
    }
    for index in ordered.indices.dropFirst()
    where ordered[index - 1] == ordered[index] {
      throw .persistedStateCorrupt(
        reason: "A revision deletion candidate set contains a duplicate revision."
      )
    }
    self.databaseID = databaseID
    self.revisions = ordered
  }

  package func contains(_ revision: DesignRevisionReference) -> Bool {
    guard revision.databaseID == databaseID else { return false }
    return revisions.contains(revision)
  }

  package func overlaps(
    _ other: DesignDatabaseRuntimeRevisionDeletionCandidateSet
  ) -> Bool {
    guard databaseID == other.databaseID else { return false }
    return revisions.contains { other.contains($0) }
  }
}
