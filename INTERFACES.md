# DesignDatabase Interface Design

Status: current contract plus explicitly marked target extensions. The provider, database, exact snapshot,
transaction, query, named-reference update, persistence, negotiation, and in-process session declarations exist
and are compiler-tested. Projection batches, continuations, borrowed record batches, traversal depth/direction,
remote streams, and the richer structured error payloads shown below are target extensions and are not callable.

The executable declaration in `Sources/` is the source of truth for current call syntax. Snippets in this document
that contain a type absent from `Sources/` describe a future contract and must not be reported as implemented.

## Database Provider

```swift
public protocol DesignDatabaseProviding: Sendable {
    func create(
        _ request: DesignDatabaseCreateRequest
    ) async throws(DesignDatabaseError) -> any DesignDatabase

    func open(
        _ request: DesignDatabaseOpenRequest
    ) async throws(DesignDatabaseError) -> any DesignDatabase
}
```

The provider owns discovery and backend selection. A request names one explicit backend; failure does not select a
different backend automatically.

## Database Session

```swift
public protocol DesignDatabase: Sendable {
    var databaseID: DesignDatabaseID { get }
    var capabilities: DesignCapabilitySet { get }

    func resolve(
        _ selector: DesignRevisionSelector
    ) async throws(DesignDatabaseError) -> DesignRevisionReference

    func snapshot(
        at revision: DesignRevisionReference
    ) async throws(DesignDatabaseError) -> DesignReadSnapshot

    func manifest(
        at revision: DesignRevisionReference
    ) async throws(DesignDatabaseError) -> DesignRevisionManifest

    func withTransaction<Result: Sendable>(
        from base: DesignRevisionReference,
        options: DesignTransactionOptions,
        _ body: (inout DesignTransaction) throws(DesignDatabaseError) -> Result
    ) async throws(DesignDatabaseError) -> DesignTransactionResult<Result>

    func compareAndSetReference(
        _ name: DesignReferenceName,
        expected: DesignRevisionReference?,
        desired: DesignRevisionReference
    ) async throws(DesignDatabaseError) -> DesignReferenceUpdate

    func close() async throws(DesignDatabaseError)
}
```

`close()` stops new operations and flushes owned persistence state. Persistence failure is reported rather than
discarded. Existing immutable snapshot leases remain valid until released. Repeated successful close is idempotent.
Public streams owned by a concrete service also provide `shutdown()` and finish their continuations.

## Revision Selection

```swift
public enum DesignRevisionSelector: Sendable, Hashable, Codable {
    case exact(DesignRevisionReference)
    case named(DesignReferenceName)
}
```

There is no implicit `latest` selector. A caller that wants the current `main` reference resolves `.named(.main)`
and receives the exact revision used by the subsequent operation.

## Snapshot

```swift
public struct DesignReadSnapshot: Sendable {
    public let revision: DesignRevisionReference
    public let stateDigest: ContentDigest
    public let schemas: [DesignSchemaDescriptor]

    public func resolve(
        _ reference: DesignEntityReference
    ) throws(DesignDatabaseError) -> DesignEntityResolution

    public func execute(
        _ query: DesignQuery
    ) throws(DesignDatabaseError) -> DesignQueryResult

    public func changes(
        since base: DesignRevisionReference,
        scope: DesignChangeScope
    ) throws(DesignDatabaseError) -> DesignChangeSet
}
```

The snapshot is a safe owner. Typed domain views are supplied by adapter protocols rather than by adding domain
methods to this type.

## Facet Adapter

```swift
public protocol DesignFacetAdapter: Sendable {
    associatedtype ReadView
    associatedtype Mutation

    static var schema: DesignFacetSchema { get }

    func withReadView<Result>(
        in snapshot: DesignReadSnapshot,
        _ body: (borrowing ReadView) throws -> Result
    ) throws -> Result

    func apply(
        _ mutation: Mutation,
        to transaction: inout DesignTransaction
    ) throws

    func validate(
        _ changes: DesignFacetChangeSet,
        in context: DesignFacetValidationContext
    ) throws -> [DesignDiagnostic]
}
```

Adapters own semantic conversion and validation. The database owns storage and atomicity. A validation diagnostic
with error severity rejects commit unless an explicit domain contract defines it as nonblocking.

## Transaction

```swift
public struct DesignTransaction: ~Copyable {
    public var baseRevision: DesignRevisionReference { get }

    public mutating func createEntity(
        facet: DesignFacetID,
        kind: DesignEntityKindID
    ) throws(DesignDatabaseError) -> DesignEntityID

    public mutating func deleteEntity(
        _ entity: DesignEntityKey
    ) throws(DesignDatabaseError)

    public mutating func apply(
        _ batch: DesignMutationBatch
    ) throws(DesignDatabaseError)

    public func resolve(
        _ entity: DesignEntityKey
    ) throws(DesignDatabaseError) -> DesignEntityResolution
}
```

The transaction is noncopyable, task-owned, and non-`Sendable`. Mutation methods are synchronous. It cannot be
stored, escaped, committed twice, or used after the closure returns.

## Transaction Result

```swift
public struct DesignTransactionResult<Value: Sendable>: Sendable {
    public let value: Value
    public let baseRevision: DesignRevisionReference
    public let candidateRevision: DesignRevisionReference
    public let stateDigest: ContentDigest
    public let changes: DesignChangeSet
    public let diagnostics: [DesignDiagnostic]
}
```

The result is a candidate revision. It does not include `approved`, `qualified`, or `releaseReady` booleans.

## Query

`DesignQuery` is a typed storage-neutral plan, not an SQL string.

```swift
public struct DesignQuery: Sendable, Hashable, Codable {
    public let source: DesignQuerySource
    public let predicate: DesignPredicate?
    public let projection: DesignProjection
    public let ordering: [DesignOrdering]
    public let limit: UInt64?
    public let continuation: DesignQueryContinuation?
    public let executionPolicy: DesignQueryExecutionPolicy
}
```

Required sources include entity IDs, facet/kind tables, exact names, hierarchy parents, connectivity adjacency,
spatial regions, cross-facet relations, dependency edges, and revision changes.

`DesignQueryExecutionPolicy` explicitly controls whether a full scan is allowed. An unavailable required index is a
typed error when scanning is forbidden.

## Query Results

```swift
public enum DesignQueryResult: Sendable {
    case entities(DesignEntityBatch)
    case records(DesignRecordBatch)
    case count(UInt64)
}
```

An owned batch can cross tasks and service boundaries. In-process high-volume adapters should prefer a
closure-scoped borrowed view:

```swift
public protocol DesignBatchBorrowing: Sendable {
    func withBorrowedRecords<Result>(
        _ body: (borrowing DesignBorrowedRecordBatch) throws -> Result
    ) throws -> Result
}
```

Borrowed views do not escape the closure. Public APIs do not return raw pointers.

## Spatial Query

The Core query expresses integer coordinate bounds and opaque domain layer keys. Geometry semantics remain in the
physical facet adapter.

```swift
public struct DesignSpatialQuery: Sendable, Hashable, Codable {
    public let container: DesignEntityReference
    public let layer: DesignIndexKey?
    public let bounds: DesignIntegerBounds
    public let relation: DesignSpatialRelation
    public let kinds: Set<DesignEntityKindID>
}
```

The database validates finite integer bounds and overflow. It does not interpret enclosure, spacing, optical
coupling, or DRC semantics.

## Connectivity Query

```swift
public struct DesignConnectivityQuery: Sendable, Hashable, Codable {
    public let start: [DesignEntityReference]
    public let relationKinds: Set<DesignRelationKindID>
    public let direction: DesignTraversalDirection
    public let maximumDepth: UInt32?
    public let ordering: DesignTraversalOrdering
}
```

Unlimited traversal still obeys cancellation and result-size limits supplied by the execution policy.

## Change Set

```swift
public struct DesignChangeSet: Sendable, Hashable, Codable {
    public let baseRevision: DesignRevisionReference
    public let targetRevision: DesignRevisionReference
    public let changes: [DesignEntityChange]
    public let digest: ContentDigest
}
```

Entity changes distinguish create, delete, field mutation, relation insertion, relation removal, and extension
payload mutation. Ordering and digest encoding are canonical.

## Named Reference Update

`compareAndSetReference` performs only database atomicity. Authorization and approval are caller responsibilities.

Failure distinguishes missing reference, expected revision mismatch, cross-database revision, unknown revision,
and persistence failure.

## Service Interface

```swift
public protocol DesignDatabaseService: Sendable {
    func negotiate(
        _ request: DesignServiceNegotiationRequest
    ) async throws(DesignServiceError) -> DesignServiceNegotiationResult

    func openSession(
        _ request: DesignServiceSessionRequest
    ) async throws(DesignServiceError) -> DesignServiceSession

    func shutdown() async
}
```

Remote transactions use a server-owned transaction lease and mutation batches. A client disconnect or lease
expiry aborts an uncommitted transaction. No remote transaction is inferred to be approved.

## Error Surface

```swift
public enum DesignDatabaseError: Error, Sendable, Equatable {
    case invalidIdentity(DesignIdentityFailure)
    case incompatibleSchema(DesignCompatibilityReport)
    case unsupportedCapability(DesignCapabilityRequirement)
    case revisionNotFound(DesignRevisionReference)
    case entityNotFound(DesignEntityReference)
    case staleHandle
    case invalidQuery(DesignQueryFailure)
    case requiredIndexUnavailable(DesignIndexRequirement)
    case transactionConflict(DesignConflictReport)
    case validationFailed([DesignDiagnostic])
    case cancelled
    case resourceExhausted(DesignResourceLimit)
    case persistence(DesignPersistenceFailure)
    case corruption(DesignCorruptionReport)
    case closed
}
```

Concrete associated failure types retain structured data. They must not embed secrets or rely on log parsing.
