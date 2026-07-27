import CircuiteFoundation

public protocol DesignFacetValidating: Sendable {
  var facetID: DesignFacetID { get }

  func validate(
    proposedEntities: [DesignEntityID: DesignEntityRecord],
    baseEntities: [DesignEntityID: DesignEntityRecord],
    changes: [DesignEntityChange]
  ) throws(DesignDatabaseError) -> [DesignDiagnostic]
}
