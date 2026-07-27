import CircuiteFoundation
import DesignDatabaseCore

public actor InProcessDesignDatabaseService {
  private let database: any DesignDatabase
  private let schemas: [DesignSchemaDescriptor]
  private let capabilities: DesignCapabilitySet
  private var isShutdown: Bool

  public init(
    database: any DesignDatabase,
    schemas: [DesignSchemaDescriptor],
    capabilities: DesignCapabilitySet
  ) {
    self.database = database
    self.schemas = schemas
    self.capabilities = capabilities
    self.isShutdown = false
  }

  public func negotiate(
    _ request: DesignServiceNegotiationRequest
  ) throws(DesignDatabaseError) -> DesignServiceNegotiationResult {
    guard !isShutdown else { throw .closed }
    let report: DesignCompatibilityReport
    do {
      report = try DesignCompatibilityNegotiator.negotiate(
        offeredSchemas: schemas,
        requiredSchemas: request.requiredSchemas,
        offeredCapabilities: capabilities,
        requiredCapabilities: request.requiredCapabilities
      )
    } catch let error {
      throw .schemaContract(error)
    }
    guard report.isCompatible else { throw .incompatibleSchema(report) }
    return DesignServiceNegotiationResult(report: report)
  }

  public func openSession(
    leaseDuration: Duration = .seconds(300)
  ) throws(DesignDatabaseError) -> DesignDatabaseServiceSession {
    guard !isShutdown else { throw .closed }
    return try DesignDatabaseServiceSession(
      database: database,
      leaseDuration: leaseDuration
    )
  }

  public func shutdown() async throws(DesignDatabaseError) {
    if isShutdown { return }
    try await database.close()
    isShutdown = true
  }
}
