import CircuiteFoundation
import Foundation

public struct DesignRevisionManifest: Sendable, Hashable, Codable {
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let schemaDigests: [DesignSchemaID: ContentDigest]
  public let changeSetDigest: ContentDigest
  public let provenance: ExecutionProvenance?
  public let createdAt: Date

  public init(
    revision: DesignRevisionReference,
    parents: [DesignRevisionReference],
    stateDigest: ContentDigest,
    schemaDigests: [DesignSchemaID: ContentDigest],
    changeSetDigest: ContentDigest,
    provenance: ExecutionProvenance?,
    createdAt: Date
  ) {
    self.revision = revision
    self.parents = parents
    self.stateDigest = stateDigest
    self.schemaDigests = schemaDigests
    self.changeSetDigest = changeSetDigest
    self.provenance = provenance
    self.createdAt = createdAt
  }
}
