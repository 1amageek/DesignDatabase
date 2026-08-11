# DesignDatabase Interface Design

Status: target public contract. The Native reference retention subset and the
framework-backed Runtime registration/container/genesis/candidate/reference/retention
paths are implemented. Candidate submission uses a persisted build intent, bounded
immutable-write/projection staging transactions, deterministic persistent close/open
resume, and a separate bounded publication transaction. The production handle exposes
exact metadata, canonical facet-root snapshots, a persistent facet projection with
exact keyset pages, closure-scoped bounded Runtime model reads, and typed close. The
other projection families, the complete recovery matrix, retained decoded-cache
performance qualification, and policy-root-complete GC remain in migration.

The declarations below are design sketches. They are not present in the current package
unless explicitly stated. The callable Native oracle is now explicitly named
`DesignDatabaseReference`; `DesignReferenceReadSnapshot`,
`DesignReferenceRevisionManifest`, and `DesignReferenceDatabaseCreateRequest` keep its
synchronous closure-based semantics separate from production names. The production
`DesignDatabaseProviding`, `DesignDatabaseHandle`, and the separately discoverable
`DesignDatabaseMaintenanceHandle` are callable for candidate,
exact-snapshot metadata/facet roots, Runtime-scoped model reads, reference, retention,
qualified exact commit abandonment, status, close, and facet semantic page/query
operations. Declarations for the remaining
projection families remain target sketches until their persistent materializations are
implemented.

The target API is single-database, exact-revision, asynchronous, plan-first, bounded,
and backend-neutral. Workspace mounts and multi-database resolution belong to Xcircuite
and are specified in `../DESIGN_WORKSPACE_ARCHITECTURE.md`.

## 1. Provider

```swift
public protocol DesignDatabaseProviding: Sendable {
  func create(
    _ request: DesignDatabaseCreateRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle

  func open(
    _ request: DesignDatabaseOpenRequest
  ) async throws(DesignDatabaseError) -> any DesignDatabaseHandle

  func close() async -> DesignDatabaseTermination
}
```

The provider is constructed by host composition from a reviewed public
`database-framework` factory. Core does not expose `StorageEngine`, a backend path,
credentials, or shutdown authority.

`create` and `open` are distinct. There is no open-or-create operation.

### Logical locator

```swift
public struct DesignDatabaseLocator: Sendable, Hashable, Codable {
  public let namespace: String
  public let segments: [String]
}
```

The locator is a bounded, canonical, secret-free logical name. Xcircuite maps a provider
profile plus locator to a physical framework factory. A locator never contains a file
path, URL, endpoint, account, credential, storage key, or backend handle.

### Create

```swift
public struct DesignDatabaseCreateRequest: Sendable {
  public let locator: DesignDatabaseLocator
  public let databaseID: DesignDatabaseID
  public let genesisRevisionID: DesignRevisionID
  public let operationID: DesignDatabaseOperationID
  public let initialSchemaBundle: DesignSchemaBundle
  public let declaredFeatureCapabilities: DesignCapabilitySet
  public let requestDigest: ContentDigest
}
```

The request fixes identity before I/O. Creation atomically publishes a catalog, genesis
revision, empty projection semantic descriptors plus initial empty materialization
bindings, `main`, and a complete operation outcome through the
framework transaction API. Identical retry returns the same result; another request with
the same operation ID is an idempotency conflict.

### Open

```swift
public struct DesignDatabaseOpenRequest: Sendable {
  public let locator: DesignDatabaseLocator
  public let expectedDatabaseID: DesignDatabaseID
  public let requiredFeatureCapabilities: DesignCapabilitySet
  public let requestedAuthorization: DesignDatabaseAuthorizationGrantSet
}
```

`DesignCapabilitySet` describes database/schema/query/service features. It never grants
permission. Authorization uses a separate closed vocabulary:

```swift
public enum DesignDatabaseAuthorizationGrant: String, Sendable, Codable {
  case read
  case proposeCandidate
  case promoteReference
  case retain
  case inspectOwnOperationOutcome
  case administer
}

public struct DesignDatabaseAuthorizationGrantSet: Sendable, Hashable, Codable {
  public let grants: [DesignDatabaseAuthorizationGrant]
}

public struct DesignAuthorizationSubjectScopeID:
  Sendable, Hashable, Codable, CustomStringConvertible
{
  public let high: UInt64
  public let low: UInt64

  public var description: String {
    FixedWidthHexadecimal.encode(high: high, low: low)
  }

  public init(high: UInt64, low: UInt64) throws {
    guard high != 0 || low != 0 else {
      throw DesignIdentityError.zeroIdentity(
        kind: "DesignAuthorizationSubjectScopeID"
      )
    }
    self.high = high
    self.low = low
  }

  public init(hexadecimalValue: String) throws {
    let words = try FixedWidthHexadecimal.decode128(
      hexadecimalValue,
      kind: "DesignAuthorizationSubjectScopeID"
    )
    try self.init(high: words.0, low: words.1)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(hexadecimalValue: container.decode(String.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

public struct DesignDatabaseOperationReference: Sendable, Hashable, Codable {
  public let databaseID: DesignDatabaseID
  public let authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID
  public let operationID: DesignDatabaseOperationID
}
```

The set is canonicalized as sorted unique values. `requestedAuthorization` is a request,
not authority. The opened handle reports effective feature capabilities and effective
authorization grants separately after host/service negotiation.

## 2. Handle

```swift
public protocol DesignDatabaseHandle: Sendable {
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var featureCapabilities: DesignCapabilitySet { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }

  func resolve(
    _ selector: DesignRevisionSelector
  ) async throws(DesignDatabaseError) -> DesignRevisionReference

  func manifest(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> DesignRevisionManifest

  func openSnapshot(
    at revision: DesignRevisionReference
  ) async throws(DesignDatabaseError) -> any DesignReadSnapshot

  func submit(
    _ plan: DesignMutationPlan
  ) async throws(DesignDatabaseError) -> DesignCommitSubmission

  func commitStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitStatus

  func compareAndSetReference(
    _ request: DesignReferenceUpdateRequest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateResult

  func referenceStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignReferenceUpdateStatus

  func retain(
    _ request: DesignRevisionRetentionRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission

  func releaseRetention(
    _ request: DesignRevisionRetentionReleaseRequest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionSubmission

  func retentionStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignRevisionRetentionStatus

  func close() async -> DesignDatabaseTermination
}
```

The handle represents one database. No method accepts a set of mutation database IDs.
Closing one handle does not silently invalidate another independently opened handle.

### Maintenance facet

The implemented Runtime handle separately conforms to the following protocol. Hosts
discover it explicitly instead of adding GC/recovery authority to ordinary design
operations.

```swift
public protocol DesignDatabaseMaintenanceHandle: Sendable {
  var databaseID: DesignDatabaseID { get }
  var authorizationSubjectScopeID: DesignAuthorizationSubjectScopeID { get }
  var authorizationGrants: DesignDatabaseAuthorizationGrantSet { get }

  func abandonCommit(
    _ request: DesignCommitAbandonmentRequest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentResult

  func commitAbandonmentStatus(
    operation: DesignDatabaseOperationReference,
    requestDigest: ContentDigest
  ) async throws(DesignDatabaseError) -> DesignCommitAbandonmentStatus
}
```

The request binds the maintenance operation, exact target operation, exact target
request digest, typed reason, and evidence digest. One framework transaction writes the
target rejection, maintenance outcome, and—when staging exists—the rejected build
intent/root plus advanced reachability generation. Unknown outcomes reconcile through
the maintenance operation reference and request digest. Only `administer` may call or
inspect this facet.

| Handle operation | Required authorization grant |
|---|---|
| resolve, manifest, openSnapshot, query | `read` |
| submit | `proposeCandidate` |
| compareAndSetReference | `promoteReference` |
| retain / release retention claim | `retain` |
| commitStatus / referenceStatus / retentionStatus for an operation owned by the authenticated subject | `inspectOwnOperationOutcome` |
| abandonCommit / commitAbandonmentStatus | `administer` |
| GC, repair, global operation inspection | `administer` |

Feature capability presence never satisfies an authorization check, and an authorization
grant never fabricates an unsupported feature.

`authorizationGrants` is the effective ceiling observed at open, not a durable bearer
credential. The host/service revalidates authorization for every protected operation and
may return a typed revocation/denial. Runtime never caches the set as a way to bypass the
current authority.

Every mutation operation record is keyed by database, the non-secret authenticated
authorization-subject scope supplied by the host/service context, and operation ID. An
operation ID is unique only inside that subject scope; the complete
`DesignDatabaseOperationReference` is the stable auditable identity. Subject scope is an
opaque stable authorization-domain identifier, not a name, account address, credential,
or revision-semantic value.

An operation reference and request digest are locators, never bearer credentials.
Caller-owned status requires both `inspectOwnOperationOutcome` and an exact subject/scope
match before lookup; `administer` may reconcile any exact operation reference. Revoking
`proposeCandidate`, `promoteReference`, or `retain` does not itself revoke outcome
inspection. If outcome inspection is also revoked, only an administrator can close the
unknown result; the caller does not receive an unauthorized disclosure.

The host/service maps the same authenticated authority to the same subject-scope ID
across reconnects for the database authorization domain. A changed or unavailable
mapping cannot be guessed; administrator reconciliation is required.

The `DesignAuthorizationSubjectScopeID` declaration belongs to CircuiteFoundation's
cross-package value floor; it owns no authentication or authorization policy.
It is a distinct validated 128-bit nonzero value. Its
canonical external encoding is exactly 32 lowercase hexadecimal digits, and `Codable`
uses that single canonical string rather than synthesized field encoding. Invalid
length, character, case, overflow, and all-zero input fail. Possessing or constructing
the public non-secret value grants no authority: only the authenticated host/service may
bind the effective scope to a handle. The authorization provider owns stable principal
to opaque-scope mapping and must not derive the public value directly from a name,
email, tenant label, credential, or other identifying plaintext.

Mutation request values carry a local `operationID`; admission qualifies it with the
provider/handle's exact database and authenticated subject scope before any idempotency
lookup or write. Every applied, rejected, in-progress, or unknown result returns that
complete operation reference. Callers cannot select a different subject scope in a
mutation request.

`DesignRevisionSelector.named` is allowed when a user starts a session or reads a
reference. The result is immediately converted to an exact revision. Dependency locks,
mutation plans, Engine execution, evidence, and release bundles use exact references
only.

## 3. Revision Manifest

```swift
public struct DesignRevisionManifest: Sendable, Hashable, Codable {
  public let revision: DesignRevisionReference
  public let parents: [DesignRevisionReference]
  public let stateDigest: ContentDigest
  public let schemaRoot: DesignSchemaRoot
  public let dependencyRoot: DesignDependencyRoot
  public let facetRoots: [DesignFacetID: DesignFacetRoot]
  public let projectionSemantics: [DesignProjectionFamily: DesignProjectionSemanticDescriptor]
  public let directChangeRoot: DesignChangeRoot
  public let provenance: ExecutionProvenance?
}
```

Every parent belongs to the same database. Cross-database design dependencies are not
revision parents.

The manifest contains semantic projection identity, not a codec/fanout-dependent
physical root:

```swift
public struct DesignProjectionSemanticDescriptor: Sendable, Hashable, Codable {
  public let family: DesignProjectionFamily
  public let semanticVersion: DesignProjectionSemanticVersion
  public let entryCount: UInt64
  public let minimumKey: DesignCanonicalKey?
  public let maximumKey: DesignCanonicalKey?
  public let canonicalSequenceDigest: ContentDigest
}

public struct DesignProjectionMaterializationReference: Sendable, Hashable, Codable {
  public let semanticDescriptorDigest: ContentDigest
  public let bindingGeneration: UInt64
  public let physicalCodecVersion: DesignProjectionPhysicalCodecVersion
  public let physicalProfileDigest: ContentDigest
  public let rootNodeDigest: ContentDigest
}

public struct DesignProjectionMaterializationBindingSet: Sendable, Hashable, Codable {
  public let bindings: [DesignProjectionFamily: DesignProjectionMaterializationReference]
}
```

The canonical sequence digest is computed from the ordered semantic entries with a
specified boundary-independent accumulator. Page size, fanout, compression, physical
codec, and tree packing do not change the revision or state digest. Runtime may publish a
new verified materialization binding for an existing semantic descriptor without
creating a design revision. A snapshot pins one exact immutable binding generation;
continuations cannot switch generation.

## 4. Direct Dependency Lock

```swift
public struct DesignDependencyLock: Sendable, Hashable, Codable {
  public let schemaVersion: Int
  public let entries: [DesignDependencyLockEntry]
}

public struct DesignDependencyLockEntry: Sendable, Hashable, Codable {
  public let dependencyID: DesignDependencyID
  public let semanticRole: String
  public let target: DesignDependencyTarget
  public let requiredSchemas: [DesignSchemaBundleMember]
  public let requiredCapabilities: [DesignCapabilityRequirement]
  public let interfaceDigest: ContentDigest
  public let retentionContractIdentity: String
}

public enum DesignDependencyTarget: Sendable, Hashable, Codable {
  case databaseRevision(DesignRevisionReference)
  case artifactContent(ArtifactID)
}
```

`DesignDependencyLockDigest.root(_:using:)` computes the canonical direct-lock root.
`DesignSemanticDependencyGraphDigest.root(_:using:)` independently computes the
location-independent transitive graph identity. `ArtifactID` is content-only;
`ArtifactReference`, `ArtifactAvailability`, provider selection, and access receipts do
not enter canonical dependency hashing.

The dependency lock contains no mount ID, provider profile, locator, endpoint,
credential, cache path, or mutable revision selector.

## 5. Cross-Database Entity Binding

```swift
public struct DesignExternalEntityBinding: Sendable, Hashable, Codable {
  public let dependencyID: DesignDependencyID
  public let entity: DesignEntityReference
  public let interfaceDigest: ContentDigest
}
```

The exact entity revision must equal the database revision named by the corresponding
dependency entry. The binding is not accepted as an intra-database relation target.

Cross-database query and availability resolution are not DesignDatabase APIs. Xcircuite
opens the dependency snapshot and supplies typed inputs to the owning domain adapter.

## 6. Snapshot

```swift
public protocol DesignReadSnapshotReading: Sendable {
  var revision: DesignRevisionReference { get }
  var parents: [DesignRevisionReference] { get }
  var stateDigest: ContentDigest { get }
  var designSchemaBundle: DesignSchemaBundle { get }
  var designSchemaBundleDigest: ContentDigest { get }
  var directDependencyLock: DesignDependencyLock { get }
  var dependencyRootDigest: ContentDigest { get }
  var semanticDependencyGraphDigest: ContentDigest { get }
  var facetRoots: [DesignFacetRoot] { get }
  var directChangeRootDigest: ContentDigest { get }
  var projectionSemantics: [DesignProjectionSemanticDescriptor] { get }
  var materializationBindings: DesignProjectionMaterializationBindingSet { get }

  func query(
    _ request: DesignQueryRequest
  ) async throws(DesignDatabaseError) -> DesignQueryPage
}

public protocol DesignReadSnapshot: DesignReadSnapshotReading {
  func close() async -> DesignSnapshotTermination
}

public struct DesignReadSnapshotView: DesignReadSnapshotReading, Sendable {
  public init(_ snapshot: any DesignReadSnapshot)
}
```

Every request is bound to the snapshot revision and its pinned materialization binding
set. A continuation cannot switch revision, schema, semantic descriptor, binding
generation, physical root, query, order, or budget.

Runtime persists the canonical direct lock in every revision manifest. Genesis stores
the canonical empty lock, ordinary candidates inherit it, and dependency-update plans
replace it explicitly. Reopen decodes and re-hashes the stored lock before exposing a
snapshot; malformed encoding or a root mismatch is corrupt state, never an empty-lock
fallback.

The public API returns bounded owned pages. `DesignReadSnapshotView` removes lifetime
termination authority but does not retain or extend the underlying lease: queries fail
with the snapshot's typed closed error after the owner closes. A local optimized
implementation may also offer a closure-scoped page borrow API, but a pointer or page
view cannot escape its page/snapshot owner.

## 7. Query

```swift
public struct DesignQueryRequest: Sendable, Hashable, Codable {
  public let source: DesignQuerySource
  public let predicate: DesignPredicate?
  public let projection: DesignProjection
  public let order: DesignCanonicalOrder
  public let budget: DesignQueryBudget
  public let continuation: DesignQueryContinuation?
}
```

P0 sources are explicit:

- entity;
- facet and kind;
- exact name;
- hierarchy occurrences;
- outgoing or incoming cross-facet occurrences;
- reverse dependency occurrences.

Spatial, connectivity, and direct-change operations use their dedicated typed requests.
They are not aliases hidden inside generic query.

### Page envelope

```swift
public struct DesignQueryPage: Sendable {
  public let revision: DesignRevisionReference
  public let schemaRoot: DesignSchemaRoot
  public let projectionSemanticDigest: ContentDigest
  public let materialization: DesignProjectionMaterializationReference
  public let rows: DesignOwnedRecordBatch
  public let continuation: DesignQueryContinuation?
  public let completion: DesignQueryCompletion
  public let report: DesignQueryResourceReport
}
```

Completion distinguishes source exhaustion, caller maximum, cancellation, and terminal
resource failure. A final page remains self-describing even when continuation is nil.

### Continuation

A continuation cryptographically or canonically binds:

- database and exact revision;
- schema and projection semantic version/digest;
- exact materialization binding generation, physical codec/profile, and root;
- normalized request and order;
- last consumed canonical key;
- page and whole-query limits;
- cumulative node-fetch, encoded-read-byte, decoded-retained-byte, output-byte,
  candidate, work, and result counters observable by DesignDatabase;
- expiry and integrity version where applicable.

Resume is keyset-based. Offset-only resume and full-result fingerprinting are not the
production circuit-scale path.

Backend-internal copied bytes and process allocation counts are not continuation
counters because the fixed public API does not expose them completely. They are retained
provider-profile benchmark evidence and must not be inferred from DesignDatabase's
observable byte counters.

### Scan policy

There is no implicit full-scan fallback. A bounded administrative scan, if supported,
uses a separate explicit operation and admission policy. An unavailable semantic
projection returns `unsupportedCapability` or `projectionUnavailable`.

## 8. Spatial Query

```swift
public struct DesignSpatialQueryRequest: Sendable, Hashable, Codable {
  public let container: DesignEntityReference
  public let layerScope: DesignLayerScope
  public let bounds: DesignIntegerBounds
  public let relation: DesignSpatialRelation
  public let budget: DesignQueryBudget
  public let continuation: DesignQueryContinuation?
}
```

Candidate identity and order are:

```text
(container, layerScope, entity, stableEntryID)
```

The page is explicitly conservative. Only the owning physical/geometry adapter may
produce an exact result after refinement. Candidate completion and exact-refinement
completion are distinct.

## 9. Connectivity Query

P0 connectivity is one-hop occurrence adjacency.

Canonical ordering includes:

```text
(matchedStart, relationKind, owner, semanticOrder, target, occurrenceID)
```

Parallel occurrences and repeated targets remain distinct. Multi-hop traversal state is
Engine-owned unless a later bounded server traversal interface is designed and can be
implemented through the fixed framework public API.

## 10. Direct Changes

```swift
public struct DesignChangeRecord: Sendable, Hashable, Codable {
  public let key: DesignChangeKey
  public let before: DesignChangeValue?
  public let after: DesignChangeValue?
}
```

P0 reads the direct change root stored by the target manifest from its exact state base.
Arbitrary two-revision comparison is a separately budgeted derived view. It cannot be
implemented by concatenating causal deltas and calling them a state diff.

## 10A. Derived Diff and Validated Disjoint Merge

`DesignDatabaseHandle.diff(_:)` compares two exact revisions under an independent
resource budget. `assessDisjointMerge(_:)` is read-only: it canonicalizes the two branch
parents and either returns a typed conflict or a candidate that still requires domain
semantic validation.

Two-parent publication is exposed separately through `DesignDisjointMergePublishing`.
Its submission binds the assessed candidate, one exact validated-state revision, the
complete `DesignCommitSubmission` that produced that revision, publication budgets, and
one canonical request digest. Runtime revalidates the commit plan, reads its exact scoped
commit status, recomputes the branch assessment, and authenticates the persisted commit
claim and outcome again inside the publication transaction. The transaction either
records a typed rejection or publishes one immutable two-parent revision plus an
operation outcome. It never changes `main`; review and reference promotion remain
separate owners.

## 11. Mutation Plan

```swift
public struct DesignMutationPlan: Sendable {
  public let operationID: DesignDatabaseOperationID
  public let databaseID: DesignDatabaseID
  public let baseRevision: DesignRevisionReference
  public let schemaRoot: DesignSchemaRoot
  public let dependencyRoot: DesignDependencyRoot
  public let requestDigest: ContentDigest
  public let manifest: DesignMutationManifest
  public let provenance: ExecutionProvenance?
  public let budget: DesignMutationBudget
}
```

The plan has one mutation database. It may record exact dependency snapshots and a
resolved dependency-graph digest as inputs, but it cannot contain mutations for them.

Large operations are bounded immutable chunks or owners referenced by the manifest. A
production plan is not one unbounded `[Operation]` array.

## 12. Commit Result and Status

```swift
public enum DesignCommitSubmission: Sendable {
  case committed(DesignCommitResult)
  case rejected(DesignCommitRejection)
  case outcomeUnknown(DesignCommitUnknown)
}

public struct DesignCommitResult: Sendable {
  public let operation: DesignDatabaseOperationReference
  public let baseRevision: DesignRevisionReference
  public let candidateRevision: DesignRevisionReference
  public let stateDigest: ContentDigest
  public let dependencyRoot: DesignDependencyRoot
  public let directChangeRoot: DesignChangeRoot
  public let diagnostics: [DesignDiagnostic]
}
```

An unknown result is not success or failure. `commitStatus` requires the complete
operation reference and request digest and reconciles persisted state.

A successful commit creates a candidate. It does not update `main` and does not imply
approval, trust, signoff, or release.

## 13. Named Reference Update

```swift
public struct DesignReferenceUpdateRequest: Sendable {
  public let operationID: DesignDatabaseOperationID
  public let name: DesignReferenceName
  public let expectedGeneration: UInt64
  public let expectedRevision: DesignRevisionReference?
  public let desiredRevision: DesignRevisionReference?
  public let requestDigest: ContentDigest
}
```

The result distinguishes:

- applied;
- precondition rejected;
- authorization rejected;
- invalid/cross-database desired revision;
- outcome unknown.

An unknown CAS result is reconciled with `referenceStatus` under the same
caller-owned/admin outcome-authorization rule as commit and retention status. Retrying
the original CAS remains idempotent, but losing `promoteReference` after submission does
not authorize Runtime to guess its outcome.

Approval policy is not part of this type. Xcircuite and DesignFlowKernel obtain
authorization before invoking it. Release references are protected by hosting policy
and retention claims.

## 14. Retention

```swift
public struct DesignRevisionRetentionRequest: Sendable {
  public let operationID: DesignDatabaseOperationID
  public let claimID: DesignRevisionRetentionID
  public let revision: DesignRevisionReference
  public let reason: DesignRevisionRetentionReason
  public let evidenceDigest: ContentDigest
  public let requestDigest: ContentDigest
}

public struct DesignRevisionRetentionReleaseRequest: Sendable {
  public let operationID: DesignDatabaseOperationID
  public let claimID: DesignRevisionRetentionID
  public let expectedRevision: DesignRevisionReference
  public let expectedGeneration: UInt64
  public let requestDigest: ContentDigest
}

public enum DesignRevisionRetentionSubmission: Sendable {
  case applied(DesignRevisionRetentionReceipt)
  case rejected(DesignRevisionRetentionRejection)
  case outcomeUnknown(DesignRevisionRetentionUnknown)
}

public enum DesignRevisionRetentionState: String, Sendable, Codable {
  case active
  case released
}

public struct DesignRevisionRetentionReceipt: Sendable {
  public let operation: DesignDatabaseOperationReference
  public let claimID: DesignRevisionRetentionID
  public let revision: DesignRevisionReference
  public let generation: UInt64
  public let reachabilityGeneration: UInt64
  public let state: DesignRevisionRetentionState
  public let outcomeDigest: ContentDigest
}

public enum DesignRevisionRetentionStatus: Sendable {
  case applied(DesignRevisionRetentionReceipt)
  case rejected(DesignRevisionRetentionRejection)
  case inProgress
  case notRecorded
  case outcomeUnknown(DesignRevisionRetentionUnknown)
}
```

Retention is a storage-semantic reachability claim, not approval. Flow and Release
decide why a claim is required. External database dependencies must refer to a revision
with verifiable retention or publication evidence.

Creating and releasing a claim are operation-identified, request-digest-bound,
idempotent state transitions. A claim ID is never reused. Its active record transitions
to a retained release tombstone, so a delayed create or release retry cannot cause an
ABA error. Release uses exact revision plus claim-generation CAS and never deletes the
revision by itself.

`DesignRevisionRetentionDigest` is the callable Core codec shared by Native, future
Runtime, and remote adapters. Canonical version 1 uses an explicit domain-separated
binary encoding for retain requests, release requests, applied outcomes, and rejected
outcomes. Fixed-width identifiers and generations are big-endian; variable-width
strings and digest components are length-prefixed. Request encodings exclude the
`requestDigest` field itself. Implementations must reject a caller-supplied request
digest or a persisted outcome digest that does not match the complete canonical
payload. Golden vectors in `DesignRevisionRetentionDigestTests` freeze this contract
independently of `Codable` or JSON representation.

The transition and its complete operation outcome are persisted atomically. Activating
or releasing a claim increments the reachability generation in the same transaction.
An unknown result is neither success nor failure; the caller reconciles it with
`retentionStatus` before deciding whether to retry. The status lookup requires the
original complete operation reference and request digest plus caller-owned outcome
authorization and subject/scope match, or `administer`. Hosting policy revalidates that
the caller may act for the claim on both create and release.

Commit, reference, and retention status share one visibility rule. For caller-owned
inspection, `notRecorded` means no matching record exists in that authenticated
subject-scoped namespace. Another subject may use the same local operation ID without a
collision or disclosure. The caller may resubmit the identical request with the same
operation ID inside its own scope, but must not invent a replacement ID to guess around
an unknown result. A different request digest under the same scoped operation ID is an
idempotency conflict visible only to that subject or an administrator.

The Native reference image also carries a monotonic persistence generation independent
of the reachability generation. A failed persist is reconciled only when the reloaded
image is structurally identical to the exact current or proposed image at the
corresponding generation. A foreign, stale, or divergent image is corruption and is
never adopted. While reconciliation is suspended, matching status returns
`inProgress`, competing mutation and close are rejected, and an unavailable
reconciliation result leaves the operation unresolved. Closing an unresolved instance
does not flush its in-memory image over an outcome that has not been proved.

The result/status contract distinguishes applied active or released state, identical
replay, precondition conflict, claim/revision mismatch, authorization rejection, and
outcome unknown. The Native reference tests cover lifecycle conflicts, authorization
revocation, lost responses, in-progress visibility, exact-image reconciliation,
restart validation, tampered digests, and delayed retries. The production Runtime must
add concurrent release-versus-GC and framework transaction/restart coverage.

## 15. Domain Adapter Contracts

The public responsibilities are interface-segregated:

```swift
public protocol DesignFacetSchemaProviding: Sendable { }
public protocol DesignImportPlanning: Sendable { }
public protocol DesignReadProjecting: Sendable { }
public protocol DesignOverlayValidating: Sendable { }
public protocol DesignDependencyRuleProviding: Sendable { }
public protocol DesignFacetMigrating: Sendable { }
```

The domain package owns database-independent semantics and a pure validator. The schema
target owns persistence representation, cross-facet constraints, and adaptation from a
bounded proposed overlay to the domain validator. Runtime owns validation execution,
budgeting, and commit admission.

One mechanical runtime adapter contributes the compiled schema and handlers to the
single exact framework registration bundle. Its mutation contract separates asynchronous
exact-base validation from synchronous deterministic materialization. Runtime persists
the validated opaque input atomically with operation claim and identity reservation;
every post-claim retry materializes from that record and cannot re-enter validation. The
adapter does not select a backend.

## 16. Compatibility Schema Contribution

EDAInteroperability maps canonical objects through the owning domain schemas. It does not
register a second canonical logical or physical facet.

Compatibility-only data such as an OpenDB OID, unknown property, source object scope, or
loss record may be supplied by:

- `OpenDBCompatibilityDatabaseSchema`, which owns only compatibility metadata models;
- `OpenDBCompatibilityRuntimeAdapter`, which mechanically contributes them to the
  runtime bundle;
- Xcircuite, which performs the actual one-time composition.

EDAInteroperability never writes framework storage directly.

## 17. Service Interface

The remote protocol mirrors the same contracts:

```swift
public protocol DesignDatabaseService: Sendable {
  func negotiate(_ request: DesignServiceNegotiationRequest) async throws
    -> DesignServiceNegotiationResult
  func openSession(
    configuration: DesignDatabaseServiceSessionConfiguration
  ) async throws
    -> any DesignDatabaseServiceSession
  func closeSession(_ sessionID: DesignDatabaseServiceSessionID) async
    -> DesignDatabaseServiceTermination
}
```

`DesignDatabaseService` and `DesignDatabaseServiceSession` are transport-neutral public
protocols. `InProcessDesignDatabaseService` and
`InProcessDesignDatabaseServiceSession` are the reference implementation. One session
identifies one exact database and authenticated subject scope. It may open exact
snapshots, query bounded pages, submit one-database plans, read caller-owned operation
status, request reference CAS, and execute operation-identified retain/release/status.
The service owns session registration and closure; the session protocol cannot bypass
that owner by closing itself.
The durable handle remains the outcome authority: session disconnect never guesses a
commit result, and a reconnect reconciles the same operation reference plus request
digest. Workspace federation, credential transport, and cross-database orchestration
remain outside the service.

`DesignDatabaseServiceQueryPageCodec` defines the first versioned binary transport
payload. Its fixed header binds the codec version, metadata byte count, and row count.
Bounded sorted-key JSON metadata carries semantic page identity and continuation state;
ordered rows carry binary canonical keys and values. Decode checks frame, metadata,
row, key, and value budgets before constructing `DesignProjectionEntry` and
`DesignQueryPage`, so Core ordering and continuation invariants remain authoritative.
This codec does not select a socket, authenticate a subject, assign deadlines, or own a
remote session. Those responsibilities belong to the separate service transport and
host-composition boundaries below.

The service transport adapter now consists of four separate responsibilities:

| Type | Responsibility |
|---|---|
| `DesignDatabaseServiceWireCodec` | Versioned request identity, operation identity, payload format, byte budgets, and SHA-256 payload integrity |
| `DesignDatabaseServiceRemoteDispatcher` | Bind one out-of-band authenticated subject scope to its owned sessions and reject scope misrouting |
| `RemoteDesignDatabaseService` | Preserve the typed service/session API and decode typed remote failures without string fallback |
| `DesignDatabaseServiceProcessWireTransport` / `DesignDatabaseServiceStandardIOHost` | Ordered UInt64-length-prefixed process exchange, deadline teardown, bounded graceful close, and disconnect cleanup |

The subject-scope ID is never accepted from a wire request. Host composition creates
`DesignDatabaseServiceAuthenticatedSubjectContext` only after authenticating the peer;
service-wide shutdown additionally requires an out-of-band shutdown authorization.
The service package provides the byte transport and host loop but does not implement a
production credential verifier or choose a database/provider executable. Xcircuite now
owns that composition: its CLI host binds one authenticated workspace mount and passes a
real managed-local negotiate/resolve/snapshot/query/shutdown/reopen child-process E2E.
Production credential verification and retained lifecycle qualification remain host
responsibilities.

## 18. Error Surface

```swift
public enum DesignDatabaseError: Error, Sendable {
  case invalidIdentity
  case invalidLocator
  case databaseAlreadyExists
  case databaseNotFound
  case databaseIdentityMismatch
  case unsupportedCapability
  case schemaMismatch
  case dependencyMismatch
  case dependencyUnavailable
  case revisionNotFound
  case revisionDeletionInProgress
  case revisionCollected
  case crossDatabaseReference
  case crossDatabaseMutation
  case projectionUnavailable
  case invalidContinuation
  case snapshotClosed
  case planBindingMismatch
  case validationFailed
  case transactionConflict
  case outcomeUnknown
  case unauthorized
  case resourceExhausted
  case corruption
  case persistence
  case service
  case cleanupFailed
  case collectionStateInvalid
}
```

Concrete associated evidence is required in the implementation. This compact list
identifies categories, not permission to replace structured failures with strings.

## 19. Current-to-Target Migration

| Current callable API | Target decision |
|---|---|
| `DesignDatabaseReferenceProviding.create` only | Kept as Native oracle; production provider now has explicit create/open |
| `withTransaction` synchronous closure | Retain as Native oracle, replace in production with immutable plan submission |
| in-memory `DesignReferenceReadSnapshot` value | Keep as Native oracle; add the production async lease owner |
| array/dictionary query results | Replace high-volume path with bounded owned semantic pages |
| revision manifest without dependency root | Add exact direct dependency root |
| value-only named-reference CAS | Add operation identity, generation, receipt, and reconciliation |
| no production retention lifecycle | Native reference retain/release/status, generation CAS, permanent claim tombstones, authorization, and lost-response reconciliation are implemented; reproduce the contract with framework-managed Runtime records |
| no durable collection lifecycle | Add visible/deleting/collected gate, collection intent, restart-before-open reconstruction, and permanent revision/materialization tombstone |
| full-image WAL | Keep reference-only; production uses framework persistence |
| in-process service | Keep reference-only until framework-backed service contract is implemented |

Backward compatibility with the current experimental API is not required. Removal or
replacement occurs only with success/failure behavioral tests and updated documentation.
