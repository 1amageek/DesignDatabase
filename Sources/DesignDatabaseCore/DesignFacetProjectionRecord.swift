import CircuiteFoundation

public struct DesignFacetProjectionRecord: Sendable, Hashable, DesignDatabaseSerializable, Comparable {
  public let facetID: DesignFacetID
  public let rootDigest: ContentDigest

  public init(
    facetID: DesignFacetID,
    rootDigest: ContentDigest
  ) {
    self.facetID = facetID
    self.rootDigest = rootDigest
  }

  public init(
    projectionEntry: DesignProjectionEntry
  ) throws(DesignDatabaseError) {
    let facet = String(decoding: projectionEntry.key.bytes, as: UTF8.self)
    guard Array(facet.utf8) == projectionEntry.key.bytes else {
      throw .corruption("A facet projection key is not valid UTF-8.")
    }
    let fields = String(decoding: projectionEntry.value, as: UTF8.self).split(
      separator: "\t",
      omittingEmptySubsequences: false
    )
    guard fields.count == 2 else {
      throw .corruption("A facet projection value is malformed.")
    }
    do {
      self.facetID = try DesignFacetID(rawValue: facet)
      self.rootDigest = try ContentDigest(
        algorithm: ContentDigestAlgorithm(rawValue: String(fields[0])),
        hexadecimalValue: String(fields[1])
      )
    } catch {
      throw .corruption("A facet projection record contains invalid identity data.")
    }
  }

  public func projectionEntry() throws(DesignDatabaseError) -> DesignProjectionEntry {
    try DesignProjectionEntry(
      key: DesignCanonicalKey(bytes: Array(facetID.rawValue.utf8)),
      value: Array(
        (rootDigest.algorithm.rawValue + "\t" + rootDigest.hexadecimalValue).utf8
      )
    )
  }

  public static func < (
    lhs: DesignFacetProjectionRecord,
    rhs: DesignFacetProjectionRecord
  ) -> Bool {
    lhs.facetID.rawValue < rhs.facetID.rawValue
  }
}
