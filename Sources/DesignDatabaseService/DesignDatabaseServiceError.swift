import CircuiteFoundation
import DesignDatabaseCore

public enum DesignDatabaseServiceError: Error, Sendable, Equatable, Codable {
  case closed
  case leaseExpired
  case backpressure(limit: UInt64)
  case sessionLimitReached(limit: UInt64)
  case snapshotNotFound(DesignDatabaseServiceSnapshotID)
  case identifierSpaceExhausted
  case incompatibleSchema(DesignCompatibilityReport)
  case operationUnavailable(operation: String)
  case transport(DesignDatabaseServiceWireTransportError)
  case database(DesignDatabaseError)
}
