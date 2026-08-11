import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseRuntimeCreationUnknown: Sendable, Hashable {
  public let operation: DesignDatabaseOperationReference
  public let requestDigest: ContentDigest

  public init(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) {
    self.operation = operation
    self.requestDigest = requestDigest
  }
}
