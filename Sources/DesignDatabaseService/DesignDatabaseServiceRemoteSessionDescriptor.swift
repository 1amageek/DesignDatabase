import CircuiteFoundation
import DesignDatabaseCore

public struct DesignDatabaseServiceRemoteSessionDescriptor:
  Sendable,
  Hashable,
  Codable
{
  public let id: DesignDatabaseServiceSessionID
  public let databaseID: DesignDatabaseID
  public let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let featureCapabilities: DesignCapabilitySet
  public let authorizationGrants: DesignDatabaseAuthorizationGrantSet
  public let genesisRevision: DesignRevisionReference

  public init(
    id: DesignDatabaseServiceSessionID,
    databaseID: DesignDatabaseID,
    authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID,
    featureCapabilities: DesignCapabilitySet,
    authorizationGrants: DesignDatabaseAuthorizationGrantSet,
    genesisRevision: DesignRevisionReference
  ) throws(DesignDatabaseServiceWireTransportError) {
    guard genesisRevision.databaseID == databaseID else {
      throw .protocolViolation(
        reason: "A remote session genesis revision belongs to another database."
      )
    }
    self.id = id
    self.databaseID = databaseID
    self.authorizationSubjectScopeID = authorizationSubjectScopeID
    self.featureCapabilities = featureCapabilities
    self.authorizationGrants = authorizationGrants
    self.genesisRevision = genesisRevision
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case databaseID
    case authorizationSubjectScopeID
    case featureCapabilities
    case authorizationGrants
    case genesisRevision
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    do {
      try self.init(
        id: container.decode(DesignDatabaseServiceSessionID.self, forKey: .id),
        databaseID: container.decode(DesignDatabaseID.self, forKey: .databaseID),
        authorizationSubjectScopeID: container.decode(
          DesignAuthorizationSubjectScopeID.self,
          forKey: .authorizationSubjectScopeID
        ),
        featureCapabilities: container.decode(
          DesignCapabilitySet.self,
          forKey: .featureCapabilities
        ),
        authorizationGrants: container.decode(
          DesignDatabaseAuthorizationGrantSet.self,
          forKey: .authorizationGrants
        ),
        genesisRevision: container.decode(
          DesignRevisionReference.self,
          forKey: .genesisRevision
        )
      )
    } catch let error as DecodingError {
      throw error
    } catch {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath,
          debugDescription: String(describing: error)
        )
      )
    }
  }
}
