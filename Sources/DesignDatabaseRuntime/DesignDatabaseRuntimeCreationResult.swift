import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimeCreationResult: Sendable, Hashable {
  public let operation: DesignDatabaseOperationReference
  public let genesisRevision: DesignRevisionReference
  public let registrationDigest: ContentDigest
  public let outcomeDigest: ContentDigest
  public let wasReplayed: Bool

  package init(
    operation: DesignDatabaseOperationReference,
    genesisRevision: DesignRevisionReference,
    registrationDigest: ContentDigest,
    outcomeDigest: ContentDigest,
    wasReplayed: Bool
  ) {
    self.operation = operation
    self.genesisRevision = genesisRevision
    self.registrationDigest = registrationDigest
    self.outcomeDigest = outcomeDigest
    self.wasReplayed = wasReplayed
  }
}
