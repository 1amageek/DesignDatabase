import CircuiteFoundation
import DesignDatabaseCore
import Foundation
import Testing

@Suite
struct DesignDatabaseAuthorizationContractTests {
  @Test
  func grantsAreCanonicalizedIndependentlyFromFeatureCapabilities() throws {
    let grants = DesignDatabaseAuthorizationGrantSet([
      .retain,
      .read,
      .retain,
      .inspectOwnOperationOutcome,
    ])
    let decoded = try JSONDecoder().decode(
      DesignDatabaseAuthorizationGrantSet.self,
      from: JSONEncoder().encode(grants)
    )

    #expect(grants.grants == [.inspectOwnOperationOutcome, .read, .retain])
    #expect(grants.contains(.read))
    #expect(!grants.contains(.administer))
    #expect(decoded == grants)
  }

  @Test
  func referenceNamesRejectRepeatedSeparators() {
    #expect(throws: DesignDatabaseError.invalidToken(
      kind: "Design reference name",
      value: "candidate//main"
    )) {
      _ = try DesignReferenceName(rawValue: "candidate//main")
    }
  }

  @Test
  func operationReferenceIncludesAuthenticatedSubjectScope() throws {
    let databaseID = try DesignDatabaseID(high: 1, low: 2)
    let operationID = try DesignDatabaseOperationID(rawValue: "commit-1")
    let first = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(high: 3, low: 4),
      operationID: operationID
    )
    let second = DesignDatabaseOperationReference(
      databaseID: databaseID,
      authorizationSubjectScopeID: try DesignAuthorizationSubjectScopeID(high: 5, low: 6),
      operationID: operationID
    )

    #expect(first != second)
    #expect(
      try JSONDecoder().decode(
        DesignDatabaseOperationReference.self,
        from: JSONEncoder().encode(first)
      ) == first
    )
  }
}
