import CircuiteFoundation

struct DesignNameIndexKey: Sendable, Hashable {
  let facetID: DesignFacetID
  let fieldID: DesignFieldID
  let value: String
}
