import CircuiteFoundation

public enum DesignDatabaseError: Error, Sendable, Equatable, DesignDatabaseSerializable {
  case invalidToken(kind: String, value: String)
  case invalidLocator(reason: String)
  case invalidSchemaBundle(reason: String)
  case invalidDependencyLock(reason: String)
  case invalidMutationPlan(reason: String)
  case invalidRevisionDiff(reason: String)
  case invalidMergeRequest(reason: String)
  case databaseAlreadyExists(DesignDatabaseLocator)
  case databaseNotFound(DesignDatabaseLocator)
  case databaseIdentityMismatch(expected: DesignDatabaseID, actual: DesignDatabaseID?)
  case idempotencyConflict(operation: DesignDatabaseOperationReference)
  case runtimeRegistrationMismatch
  case unsupportedCapability(DesignCapabilityID)
  case outcomeUnknown(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  )
  case schemaContract(SchemaCompatibilityError)
  case incompatibleSchema(DesignCompatibilityReport)
  case crossDatabaseReference(expected: DesignDatabaseID, actual: DesignDatabaseID)
  case revisionNotFound(DesignRevisionReference)
  case revisionDeleting(DesignRevisionReference)
  case revisionCollected(DesignRevisionReference)
  case referenceNotFound(DesignReferenceName)
  case entityNotFound(DesignEntityKey)
  case entityAlreadyExists(DesignEntityKey)
  case facetMismatch(entity: DesignEntityID, expected: DesignFacetID, actual: DesignFacetID)
  case kindMismatch(entity: DesignEntityID, expected: DesignEntityKindID, actual: DesignEntityKindID)
  case unknownFacet(DesignFacetID)
  case unknownEntityKind(facet: DesignFacetID, kind: DesignEntityKindID)
  case unknownField(DesignFieldID)
  case unknownRelation(DesignRelationKindID)
  case missingRequiredField(entity: DesignEntityID, field: DesignFieldID)
  case uniquenessViolation(
    facet: DesignFacetID,
    kind: DesignEntityKindID,
    constraint: DesignUniqueConstraintID,
    first: DesignEntityKey,
    second: DesignEntityKey
  )
  case relationTargetMissing(source: DesignEntityID, target: DesignEntityID)
  case invalidSpatialBounds
  case invalidQuery(String)
  case projectionUnavailable(DesignProjectionFamily)
  case invalidQueryContinuation(String)
  case requiredIndexUnavailable(DesignIndexKind)
  case transactionConflict(expected: DesignRevisionReference?, actual: DesignRevisionReference?)
  case validationFailed([DesignDiagnostic])
  case cancelled
  case resourceExhausted(limit: UInt64, requested: UInt64)
  case generationExhausted(kind: String)
  case unauthorized(
    grant: DesignDatabaseAuthorizationGrant,
    subjectScopeID: DesignAuthorizationSubjectScopeID
  )
  case contentDigest(String)
  case persistence(String)
  case corruption(String)
  case closed

  public var errorDescription: String? {
    switch self {
    case .invalidToken(let kind, let value):
      return "\(kind) is invalid: \(value)"
    case .invalidLocator(let reason):
      return "Design database locator is invalid: \(reason)"
    case .invalidSchemaBundle(let reason):
      return "Design schema bundle is invalid: \(reason)"
    case .invalidDependencyLock(let reason):
      return "Design dependency lock is invalid: \(reason)"
    case .invalidMutationPlan(let reason):
      return "Design mutation plan is invalid: \(reason)"
    case .invalidRevisionDiff(let reason):
      return "Design revision diff is invalid: \(reason)"
    case .invalidMergeRequest(let reason):
      return "Design disjoint merge request is invalid: \(reason)"
    case .databaseAlreadyExists:
      return "A design database already exists at the requested logical locator."
    case .databaseNotFound:
      return "No design database exists at the requested logical locator."
    case .databaseIdentityMismatch(let expected, let actual):
      return "Database identity does not match \(expected); actual is \(actual?.description ?? "unavailable")."
    case .idempotencyConflict:
      return "The scoped operation identifier is already bound to another request."
    case .runtimeRegistrationMismatch:
      return "The persisted database registration does not match the attached runtime."
    case .unsupportedCapability(let capability):
      return "Required capability \(capability.rawValue) is unavailable."
    case .outcomeUnknown:
      return "The database operation outcome is unknown and requires reconciliation."
    case .schemaContract(let error):
      return error.errorDescription ?? "Schema compatibility contract failed."
    case .incompatibleSchema:
      return "The requested schema set is incompatible."
    case .crossDatabaseReference(let expected, let actual):
      return "Reference belongs to database \(actual), expected \(expected)."
    case .revisionNotFound(let revision):
      return "Revision \(revision.revisionID) was not found."
    case .revisionDeleting(let revision):
      return "Revision \(revision.revisionID) is unavailable while collection is in progress."
    case .revisionCollected(let revision):
      return "Revision \(revision.revisionID) has been collected."
    case .referenceNotFound(let reference):
      return "Named reference \(reference.rawValue) was not found."
    case .entityNotFound(let entity):
      return "Entity \(entity.entityID) was not found."
    case .entityAlreadyExists(let entity):
      return "Entity \(entity.entityID) already exists."
    case .facetMismatch(let entity, let expected, let actual):
      return "Entity \(entity) facet \(actual.rawValue) does not match \(expected.rawValue)."
    case .kindMismatch(let entity, let expected, let actual):
      return "Entity \(entity) kind \(actual.rawValue) does not match \(expected.rawValue)."
    case .unknownFacet(let facet):
      return "Facet \(facet.rawValue) is not registered."
    case .unknownEntityKind(let facet, let kind):
      return "Entity kind \(kind.rawValue) is not registered in facet \(facet.rawValue)."
    case .unknownField(let field):
      return "Field \(field.rawValue) is not registered."
    case .unknownRelation(let relation):
      return "Relation \(relation.rawValue) is not registered."
    case .missingRequiredField(let entity, let field):
      return "Entity \(entity) is missing required field \(field.rawValue)."
    case .uniquenessViolation(let facet, let kind, let constraint, let first, let second):
      return "Entities \(first.entityID) and \(second.entityID) violate unique constraint \(constraint.rawValue) for \(facet.rawValue)/\(kind.rawValue)."
    case .relationTargetMissing(let source, let target):
      return "Entity \(source) refers to missing entity \(target)."
    case .invalidSpatialBounds:
      return "Spatial bounds are invalid."
    case .invalidQuery(let reason):
      return "Query is invalid: \(reason)"
    case .projectionUnavailable(let family):
      return "Projection \(family.rawValue) is unavailable for the exact revision."
    case .invalidQueryContinuation(let reason):
      return "Query continuation is invalid: \(reason)"
    case .requiredIndexUnavailable(let index):
      return "Required \(index.rawValue) index is unavailable."
    case .transactionConflict:
      return "The named reference changed before publication."
    case .validationFailed:
      return "Facet validation rejected the transaction."
    case .cancelled:
      return "The database operation was cancelled."
    case .resourceExhausted(let limit, let requested):
      return "The operation requested \(requested) records; limit is \(limit)."
    case .generationExhausted(let kind):
      return "\(kind) cannot advance because its generation space is exhausted."
    case .unauthorized(let grant, let subjectScopeID):
      return "Subject scope \(subjectScopeID) is not authorized for \(grant.rawValue)."
    case .contentDigest(let reason):
      return "Canonical content digest failed: \(reason)"
    case .persistence(let reason):
      return "Persistence failed: \(reason)"
    case .corruption(let reason):
      return "Database corruption was detected: \(reason)"
    case .closed:
      return "The database is closed."
    }
  }
}
