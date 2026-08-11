import CircuiteFoundation
import CircuiteFoundationCrypto
import DesignDatabaseCore

public struct NativeDesignDatabaseProvider: DesignDatabaseReferenceProviding {
  private let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  private let requestedAuthorization: DesignDatabaseAuthorizationGrantSet
  private let authorizer: any DesignDatabaseAuthorizing
  private let persistence: (any DesignDatabasePersisting)?
  private let digester: any ContentDigesting
  private let identifierGenerator: RandomDesignIdentifierGenerator
  private let validators: [any DesignFacetValidating]

  public init(
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    requestedAuthorization: DesignDatabaseAuthorizationGrantSet,
    authorizer: any DesignDatabaseAuthorizing,
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init(),
    validators: [any DesignFacetValidating] = []
  ) {
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.requestedAuthorization = requestedAuthorization
    self.authorizer = authorizer
    self.persistence = persistence
    self.digester = digester
    self.identifierGenerator = identifierGenerator
    self.validators = validators
  }

  public init(
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    grantedAuthorization: DesignDatabaseAuthorizationGrantSet,
    persistence: (any DesignDatabasePersisting)? = nil,
    digester: any ContentDigesting = SHA256ContentDigester(),
    identifierGenerator: RandomDesignIdentifierGenerator = .init(),
    validators: [any DesignFacetValidating] = []
  ) {
    let authority = NativeDesignDatabaseAuthorizationAuthority(
      grantsBySubjectScope: [
        authorizationSubjectScopeID: grantedAuthorization
      ]
    )
    self.init(
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      requestedAuthorization: grantedAuthorization,
      authorizer: authority,
      persistence: persistence,
      digester: digester,
      identifierGenerator: identifierGenerator,
      validators: validators
    )
  }

  public func create(
    _ request: DesignReferenceDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseReference {
    let authorizationGrants = try await authorizer.authorizeRequestedGrants(
      requestedAuthorization,
      for: authorizationSubjectScopeID
    )
    let database = try NativeDesignDatabase(
      request: request,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      authorizationGrants: authorizationGrants,
      authorizer: authorizer,
      persistence: persistence,
      digester: digester,
      identifierGenerator: identifierGenerator
    )
    try await database.persistInitialState()
    return database
  }

  public func open() async throws(DesignDatabaseError) -> any DesignDatabaseReference {
    let authorizationGrants = try await authorizer.authorizeRequestedGrants(
      requestedAuthorization,
      for: authorizationSubjectScopeID
    )
    guard let persistence else {
      throw .persistence("No persistence backend is configured.")
    }
    guard let image = try await persistence.load() else {
      throw .persistence("No database image exists at the configured location.")
    }
    return try NativeDesignDatabase(
      image: image,
      validators: validators,
      authorizationSubjectScopeID: authorizationSubjectScopeID,
      authorizationGrants: authorizationGrants,
      authorizer: authorizer,
      persistence: persistence,
      digester: digester,
      identifierGenerator: identifierGenerator
    )
  }
}
