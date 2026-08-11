import CircuiteFoundation
import DesignDatabaseCore

public actor NativeDesignDatabaseAuthorizationAuthority: DesignDatabaseAuthorizing {
  private var grantsBySubjectScope: [
    DesignAuthorizationSubjectScopeID: DesignDatabaseAuthorizationGrantSet
  ]

  public init(
    grantsBySubjectScope: [
      DesignAuthorizationSubjectScopeID: DesignDatabaseAuthorizationGrantSet
    ]
  ) {
    self.grantsBySubjectScope = grantsBySubjectScope
  }

  public func authorizeRequestedGrants(
    _ requestedGrants: DesignDatabaseAuthorizationGrantSet,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) throws(DesignDatabaseError) -> DesignDatabaseAuthorizationGrantSet {
    let available = grantsBySubjectScope[subjectScopeID]
      ?? DesignDatabaseAuthorizationGrantSet([])
    guard requestedGrants.isSubset(of: available) else {
      guard let denied = requestedGrants.grants.first(where: { !available.contains($0) }) else {
        throw .corruption("Authorization subset evaluation produced an inconsistent result.")
      }
      throw .unauthorized(
        grant: denied,
        subjectScopeID: subjectScopeID
      )
    }
    return requestedGrants
  }

  public func authorize(
    _ grant: DesignDatabaseAuthorizationGrant,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) throws(DesignDatabaseError) {
    guard grantsBySubjectScope[subjectScopeID]?.contains(grant) == true else {
      throw .unauthorized(
        grant: grant,
        subjectScopeID: subjectScopeID
      )
    }
  }

  public func replaceGrants(
    _ grants: DesignDatabaseAuthorizationGrantSet,
    for subjectScopeID: DesignAuthorizationSubjectScopeID
  ) {
    grantsBySubjectScope[subjectScopeID] = grants
  }
}
