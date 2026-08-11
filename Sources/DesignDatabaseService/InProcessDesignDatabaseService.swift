import CircuiteFoundation
import DesignDatabaseCore

public actor InProcessDesignDatabaseService: DesignDatabaseService {
  private let database: any DesignDatabaseHandle
  private let schemas: [DesignSchemaDescriptor]
  private let configuration: DesignDatabaseServiceConfiguration
  private var isShutdown = false
  private var nextSessionID: UInt64 = 0
  private var sessions: [
    DesignDatabaseServiceSessionID: InProcessDesignDatabaseServiceSession
  ] = [:]

  public init(
    database: any DesignDatabaseHandle,
    schemas: [DesignSchemaDescriptor],
    configuration: DesignDatabaseServiceConfiguration
  ) {
    self.database = database
    self.schemas = schemas
    self.configuration = configuration
  }

  public func negotiate(
    _ request: DesignServiceNegotiationRequest
  ) async throws(DesignDatabaseServiceError) -> DesignServiceNegotiationResult {
    guard !isShutdown else { throw .closed }
    let report: DesignCompatibilityReport
    do {
      report = try DesignCompatibilityNegotiator.negotiate(
        offeredSchemas: schemas,
        requiredSchemas: request.requiredSchemas,
        offeredCapabilities: database.featureCapabilities,
        requiredCapabilities: request.requiredCapabilities
      )
    } catch let error {
      throw .database(.schemaContract(error))
    }
    guard report.isCompatible else { throw .incompatibleSchema(report) }
    return DesignServiceNegotiationResult(report: report)
  }

  public func openSession(
    configuration: DesignDatabaseServiceSessionConfiguration
  ) async throws(DesignDatabaseServiceError) -> any DesignDatabaseServiceSession {
    guard !isShutdown else { throw .closed }
    guard let sessionCount = UInt64(exactly: sessions.count),
          sessionCount < self.configuration.maximumSessionCount else {
      throw .sessionLimitReached(
        limit: self.configuration.maximumSessionCount
      )
    }
    let (nextID, overflow) = nextSessionID.addingReportingOverflow(1)
    guard !overflow else { throw .identifierSpaceExhausted }
    let sessionID = try DesignDatabaseServiceSessionID(rawValue: nextID)
    let session = InProcessDesignDatabaseServiceSession(
      id: sessionID,
      database: database,
      configuration: configuration
    )
    nextSessionID = nextID
    sessions[sessionID] = session
    return session
  }

  public func closeSession(
    _ sessionID: DesignDatabaseServiceSessionID
  ) async -> DesignDatabaseServiceTermination {
    guard let session = sessions.removeValue(forKey: sessionID) else {
      return .alreadyClosed
    }
    return await session.shutdown()
  }

  public func shutdown() async -> DesignDatabaseTermination {
    guard !isShutdown else { return .alreadyClosed }
    isShutdown = true
    let ownedSessions = sessions
      .sorted { $0.key < $1.key }
      .map(\.value)
    sessions.removeAll(keepingCapacity: false)
    for session in ownedSessions {
      _ = await session.shutdown()
    }
    return await database.close()
  }
}
