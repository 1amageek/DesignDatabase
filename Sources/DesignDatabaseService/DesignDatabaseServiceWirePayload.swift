import CircuiteFoundation
import DesignDatabaseCore

public enum DesignDatabaseServiceWirePayload {
  public struct Empty: Sendable, Codable {
    public init() {}
  }

  public struct SessionReference: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID

    public init(sessionID: DesignDatabaseServiceSessionID) {
      self.sessionID = sessionID
    }
  }

  public struct SessionValue<Value: Sendable & Codable>: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID
    public let value: Value

    public init(
      sessionID: DesignDatabaseServiceSessionID,
      value: Value
    ) {
      self.sessionID = sessionID
      self.value = value
    }
  }

  public struct OpenSnapshot: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID
    public let revision: DesignRevisionReference

    public init(
      sessionID: DesignDatabaseServiceSessionID,
      revision: DesignRevisionReference
    ) {
      self.sessionID = sessionID
      self.revision = revision
    }
  }

  public struct CloseSnapshot: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID
    public let snapshotID: DesignDatabaseServiceSnapshotID

    public init(
      sessionID: DesignDatabaseServiceSessionID,
      snapshotID: DesignDatabaseServiceSnapshotID
    ) {
      self.sessionID = sessionID
      self.snapshotID = snapshotID
    }
  }

  public struct Query: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID
    public let snapshotID: DesignDatabaseServiceSnapshotID
    public let request: DesignQueryRequest

    public init(
      sessionID: DesignDatabaseServiceSessionID,
      snapshotID: DesignDatabaseServiceSnapshotID,
      request: DesignQueryRequest
    ) {
      self.sessionID = sessionID
      self.snapshotID = snapshotID
      self.request = request
    }
  }

  public struct OperationStatus: Sendable, Codable {
    public let sessionID: DesignDatabaseServiceSessionID
    public let operation: DesignDatabaseOperationReference
    public let requestDigest: ContentDigest

    public init(
      sessionID: DesignDatabaseServiceSessionID,
      operation: DesignDatabaseOperationReference,
      requestDigest: ContentDigest
    ) {
      self.sessionID = sessionID
      self.operation = operation
      self.requestDigest = requestDigest
    }
  }
}
