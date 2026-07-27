import CircuiteFoundation
import DesignDatabaseCore

public struct NativeDesignDatabaseProvider: DesignDatabaseProviding {
  private let persistence: (any DesignDatabasePersisting)?
  private let digester: any ContentDigesting
  private let identifierGenerator: RandomDesignIdentifierGenerator
  private let validators: [any DesignFacetValidating]

  public init(
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init(),
    validators: [any DesignFacetValidating] = []
  ) {
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.validators = validators
  }

  public func create(
    _ request: DesignDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabase {
    let database = try NativeDesignDatabase(
      request: request,
      persistence: persistence,
      digester: digester,
      identifierGenerator: identifierGenerator
    )
    try await database.persistInitialState()
    return database
  }

  public func open() async throws(DesignDatabaseError) -> any DesignDatabase {
    guard let persistence else {
      throw .persistence("No persistence backend is configured.")
    }
    guard let image = try await persistence.load() else {
      throw .persistence("No database image exists at the configured location.")
    }
    return try NativeDesignDatabase(
      image: image,
      validators: validators,
      persistence: persistence,
      digester: digester,
      identifierGenerator: identifierGenerator
    )
  }
}
