# DesignDatabase Requirements

Status: target requirements tracked against the callable implementation.

“Implemented” requires a real success and failure path. A type, document, generated
schema, build, or empty round trip is not implementation evidence.

## Implementation Status

| Area | Status | Evidence / gap |
|---|---|---|
| Domain-neutral Core | Implemented in reference | Core depends on CircuiteFoundation and no domain package |
| Multiple independent database values | Implemented in reference | Native providers can create separate instances without global registration |
| Immutable revisions and candidate separation | Implemented in reference | Native transaction produces a candidate; named-reference promotion is separate |
| Exact entity/revision identity | Implemented in reference | Database/revision/facet/kind mismatches fail |
| In-memory projections | Implemented in reference | Nine snapshot projection families exist, but use materialized Swift values |
| Recovery | Implemented in reference | Full-image WAL/reopen validation plus monotonic exact-image lost-response reconciliation; not the production persistence path |
| Retention lifecycle | Implemented in reference | Canonical binary request/outcome digests, subject-scoped replay, generation CAS, permanent tombstones, authorization revalidation, and unknown-result reconciliation |
| Service | Partial production surface | Typed remote proxy/dispatcher, digest-bound frames, binary query pages, standard-I/O host, child-process transport, subject-scope routing, deadline teardown, and a real managed-local child-process database session execute; production credential mapping and wider lifecycle qualification remain |
| Fixed-framework production Runtime | Partial callable implementation | Public fixed-framework target provides registration, create/open, permanent identity reservation, candidate/reference/retention transactions, canonical facet-root manifests, contributed projection bootstrap, unchanged-root inheritance, existing-family immutable path-copy, exact scoped reads, receipts, and status; recovery/GC remain |
| Direct dependency lock | Root binding implemented | Revision manifests persist dependency-root and semantic-graph digests and candidate admission rejects stale roots; exact dependency entries and updates remain |
| Workspace multi-database use | First managed-local runtime implemented | Xcircuite schema v4 stores typed secret-free mounts and its explicit session opens required mounts through the public framework; exact graph/effective-grant evidence/ledger admission remain |
| Persistent semantic pages/keyset cursor | Partial callable implementation | Framework-backed immutable B+tree pages and exact keyset cursor execute facet and contributed entity queries across SQLite reopen; semantic-v2 identity is independent of physical-codec-v2 packing, and exact-base updates execute split/merge/root-collapse path-copy. Real domain mappings, family-specific semantics, cache/performance, and circuit-scale retained evidence remain |
| Domain schema adapters | Compile-integrated; qualification pending | Nine P0 host integration packages exist and register through the Runtime boundary, but still persist facet documents without object-level entity/relation projection changes; migration and retained round-trip evidence remain |
| OpenDB compatibility | Partial outside package | Neutral mapping exists in EDAInteroperability; C ABI/corpus/service are absent |
| Production readiness | Not achieved | Framework Runtime, real domain data, failure/recovery, service, the remaining DesignDatabase product matrix, and performance gates remain. Foundation Core and the serialization-disabled DesignDatabaseCore probe now run identically on Native, pinned WASI, and pinned Embedded WASM; Native/Persistence/Runtime/Service portability qualification remains |

## P0 Functional Requirements

| ID | Requirement |
|---|---|
| DDB-001 | Core depends only on CircuiteFoundation; Runtime additionally depends on the fixed database stack, but neither depends on a domain package or concrete backend. |
| DDB-002 | Use only the supported public API of pinned `database-framework`; do not patch, fork, vendor, use private API, copy generic execution, or call `storage-kit` directly. |
| DDB-003 | Expose distinct idempotent create and open operations; no open-or-create behavior. |
| DDB-004 | Atomically create a catalog, exact schema root, genesis revision, empty projection semantic descriptors and initial empty materialization bindings, `main`, and complete creation outcome through one framework transaction. |
| DDB-005 | Validate exact compiled framework registration, physical migration completion, DesignDatabase catalog identity, schema/feature-capability profile, and required projection readiness before publishing a handle. |
| DDB-006 | Represent every design state as an immutable exact revision manifest with parents, state/schema/dependency/facet/change roots, boundary-independent projection semantic descriptors/digests, and provenance; physical materialization roots are not revision identity. |
| DDB-007 | Provide asynchronous immutable exact snapshot lease owners with explicit observable close and bounded read operations. |
| DDB-008 | Accept one immutable mutation plan bound to one database, exact base revision, schema root, dependency root, operation identity, request digest, and resource budget. |
| DDB-009 | Reject every cross-database mutation before plan admission. Cross-database snapshots may be exact read inputs only. |
| DDB-010 | Prepare and validate outside framework retry, stage only fixed immutable pages, and atomically publish one complete candidate manifest and receipt or no revision. |
| DDB-011 | Never reuse database-scoped entity, relation-occurrence, or spatial-entry identities. |
| DDB-012 | Persist an immutable direct dependency lock containing exact revision/content targets, roles, required schema/feature capability, interface digest, and immutable publication/retention-contract identity. |
| DDB-013 | Exclude mounts, paths, provider profiles, endpoints, credentials, caches, and mutable named selectors from the dependency lock and state digest. |
| DDB-014 | Provide explicit cross-database entity bindings through a dependency entry and exact `DesignEntityReference`; do not coerce them to intra-database relations. |
| DDB-015 | Maintain exact schema bundles without reinterpreting old revisions through the currently compiled adapter. |
| DDB-016 | Separate generic framework validation, Runtime binding/publication validation, domain pure validation, schema-adapter overlay validation, and Engine verification. |
| DDB-017 | Preserve stable relation-occurrence identity, ordered/repeated target semantics, and typed occurrence attributes. |
| DDB-018 | Maintain revision-bound entity, facet, name, hierarchy, connectivity, spatial, cross-facet, direct-change, and dependency projections. |
| DDB-019 | Persist circuit-scale projections as bounded immutable content-addressed application pages through framework model/transaction APIs. |
| DDB-020 | Use exact keyset continuation bound to revision/schema/projection/query/order/budget/last key; do not use offset-only or prior-result fingerprint resume for the high-volume path. |
| DDB-021 | Reject unavailable high-volume access paths with a typed error; do not silently run a full scan or materialize all rows. |
| DDB-022 | Return self-describing bounded owned pages with distinct source-exhausted, caller-maximum, cancelled, and resource-failure completion. |
| DDB-023 | Return spatial candidates as conservative and require domain-owned exact geometry refinement. |
| DDB-024 | Restrict P0 connectivity to bounded one-hop occurrence adjacency with stable canonical order. |
| DDB-025 | Store one typed key/before/after direct change root for each target manifest's exact state base. |
| DDB-026 | Persist complete create/commit/reference operation outcomes and reconcile unknown outcomes without guessing. |
| DDB-027 | Update named references through operation-identified exact revision+generation CAS separate from candidate commit. |
| DDB-028 | Provide operation-identified, request-digest-bound, idempotent retain and exact revision+generation CAS release operations with status reconciliation; released claim IDs remain tombstoned and are never reused. Retention reachability protects published dependencies, active snapshots, named refs, receipts, runs, and release bundles. |
| DDB-029 | Detect missing/corrupt catalog, schema, dependency, revision, page, reference, or receipt state and fail without partial successful data. |
| DDB-030 | Keep OpenDB/OpenROAD/XLS concepts, C/C++ dependencies, process execution, and compatibility loss outside Core and Runtime. |
| DDB-031 | Separate projection semantic identity from physical materialization: verified repack/fanout/codec/compression changes publish a new binding generation without changing revision or state digest, and snapshots pin one generation. |
| DDB-032 | Persist projection materializations as balanced immutable copy-on-write B+trees with equal leaf depth, checked range coverage, minimum/maximum occupancy, split/merge rebalancing, bounded node bytes, and path-copy updates. |
| DDB-033 | Atomically pair every staged node batch with its authenticated intent-progress update and protect incremental GC with persisted reachability-generation checks, maintenance-authority identity, epoch-bound frontiers, bounded candidate-set-scoped exact revision/materialization deletion admission, and crash restart. Snapshot open registers a pending lease before resolving roots and performs no persistent pin write; unrelated lease churn does not invalidate the sweep. |
| DDB-034 | Keep feature capabilities and authorization grants as separate types; read, propose candidate, promote reference, retain, inspect-own-operation-outcome, and administer are authorization grants. Operation ID plus request digest is never a bearer credential. |
| DDB-035 | Key each operation outcome by database + non-secret authenticated subject scope + local operation ID. Caller-owned commit/reference/retention status requires the exact scoped reference plus inspect-own-operation-outcome; administer may reconcile any exact reference. Local IDs may repeat across scopes without collision/disclosure, and mutation-grant revocation does not guess the outcome. |
| DDB-035A | Represent authorization subject scope as a distinct validated nonzero 128-bit value with one canonical 32-lowercase-hex encoding and identical initializer/decoder validation. The value grants no authority, contains no direct identifying data, and only authenticated host/service context may bind it to a handle. |
| DDB-035B | Expose commit abandonment only through a separately discoverable maintenance interface requiring `administer`. Bind its operation outcome to the exact target operation, target request digest, typed reason, and evidence digest. Pre-intent abandonment writes only terminal outcomes; active-staging abandonment atomically rejects the build intent/root, advances reachability generation, writes the target rejection, and persists a reconcilable maintenance outcome. |
| DDB-036 | Before the first node deletion, atomically publish an operation-identified collection intent and transition the exact revision or retired-materialization lifecycle to deleting. Exact open and new root publication reject deleting/collected identities; restart reconstructs every nonterminal admission before serving opens; completion writes a permanent collected tombstone and receipt. |

## P1 Functional Requirements

| ID | Requirement |
|---|---|
| DDB-101 | Provide deterministic disjoint-change assessment and separate validated two-parent publication. Publication must re-assess the exact branches, authenticate the persisted one-parent validation commit, require affected facets in the resulting dependency context, leave named references unchanged, and retain typed rejection/unknown outcomes. |
| DDB-102 | Provide a separately budgeted derived state diff between arbitrary exact revisions. |
| DDB-103 | Provide resumable exact-revision change streams with backpressure and explicit shutdown. |
| DDB-104 | Provide a protocol-neutral remote service with identical local/remote identity, query, plan, error, and close semantics. |
| DDB-105 | Provide CLI create, open, inspect, query, diff, verify, reference, retention, import, and export operations without duplicating framework command execution. |
| DDB-106 | Add safe decoded-page caching and revision page sharing with explicit byte budgets and lease-aware eviction. |
| DDB-107 | Add closure-scoped borrowed page views only where retained measurement proves a material benefit. |
| DDB-108 | Adapt framework physical checkpoint/compaction/accounting without changing semantic revision identity. |
| DDB-109 | Provide compatibility-only schema contribution for external IDs/properties/loss records without defining canonical domain objects. |
| DDB-110 | Qualify semantically equivalent OpenDB workloads and external client behavior through EDAInteroperability. |

## Correctness Requirements

| ID | Requirement |
|---|---|
| DDB-C01 | Missing, unsupported, malformed, unauthorized, conflicting, cancelled, exhausted, or corrupt work never returns an empty or fabricated success. |
| DDB-C02 | A native failure never silently invokes an external backend. |
| DDB-C03 | A revision never observes partially persisted facet or projection pages. |
| DDB-C04 | Every persisted/hashed/paged result has a complete canonical order and stable identity. |
| DDB-C05 | Every Engine input and plan records exact base and dependency revisions; no implicit `latest` is allowed. |
| DDB-C06 | One plan and one commit operation mutate exactly one database ID. |
| DDB-C07 | Framework retry never invokes caller code, a validator, external tool, event sink, clock, or randomness. |
| DDB-C08 | Generic framework schema/index/migration failures remain framework-owned typed failures and are not reimplemented or defaulted by DesignDatabase. |
| DDB-C09 | Dependency availability cannot change the semantic identity of a revision. Another path/provider for identical content is allowed; another revision/content digest is not. |
| DDB-C10 | Cross-database bindings resolve only through the exact dependency entry and never participate in an intra-database transaction. |
| DDB-C11 | Named-reference promotion, approval, and release remain distinct state transitions and authorities. |
| DDB-C12 | A commit or reference outcome stays unknown until matching persisted evidence proves a terminal result. |
| DDB-C13 | Page resume advances from the last consumed canonical key and cannot omit or duplicate a row at a boundary. |
| DDB-C14 | Parallel relation occurrences and repeated targets remain distinct through schema, storage, query, cursor, change, and export. |
| DDB-C15 | Spatial candidate completion cannot be reported as exact geometry completion. |
| DDB-C16 | Existing revisions retain their exact schema/dependency interpretation after physical or facet migration. |
| DDB-C17 | A snapshot/page borrow cannot outlive its owner and no pointer escapes a synchronous borrow. |
| DDB-C18 | Native, WASM, and Embedded share the same logical synchronization, Sendable, ownership, and shutdown contract. |
| DDB-C19 | `.xcircuite` references DesignDatabase state but never becomes an alternate entity/revision/index/WAL store. |
| DDB-C20 | Standard import/export is exact-revision-bound and every semantic loss is explicit. |
| DDB-C21 | Physical projection rebuilds preserve the exact semantic descriptor and query result digest; a continuation never switches physical binding generation. |
| DDB-C22 | A storage scan continuation alone never authorizes GC deletion; every delete batch revalidates the persisted reachability generation and materialization lease fence. |

## Performance Requirements

| ID | Requirement |
|---|---|
| DDB-P01 | Define corpus, scale, backend profile, hardware, build, cache state, latency/throughput, memory, allocation, copy, and storage-amplification budgets before optimization. |
| DDB-P02 | Benchmark entity, hierarchy, connectivity, spatial candidate/refinement, dependency update, plan commit, snapshot/cache, direct change, and service page paths. |
| DDB-P03 | A high-volume continuation uses keyset traversal and never rescans or fingerprints all preceding pages. |
| DDB-P04 | Peak query memory is bounded by admitted traversal, cache, encoded-page, decoded-page, and output-page budgets rather than corpus size. |
| DDB-P05 | Peak plan preparation memory is bounded by admitted chunk/page/overlay budgets rather than total mutation count. |
| DDB-P06 | Read-only operations publish no DesignDatabase mutation. |
| DDB-P07 | Independent snapshot reads are not serialized through a DesignDatabase actor. |
| DDB-P08 | Every zero-copy, copy reduction, cache, compression, or unsafe claim includes measured allocations/copied bytes and unchanged reference semantics. |
| DDB-P09 | Compare semantically equivalent physical-design operations with OpenDB where possible, including identity and loss differences. |
| DDB-P10 | A backend profile that misses a required retained workload is not production-qualified; the result does not authorize framework modification or storage bypass. |
| DDB-P11 | Checked tree profile invariants bound lookup to `O(log N)` node fetches and paging to `O(log N + visited page nodes)`; retained tests cover worst-case height, occupancy, split/merge, and head insertion. |
| DDB-P12 | Continuation accounting includes only DesignDatabase-observable node fetches and encoded-read/decoded-retained/output bytes; backend-internal allocations/copied bytes are retained benchmark evidence. |

## Verification Requirements

| Area | Required evidence |
|---|---|
| Fixed dependency | Exact stack pin, public import audit, no private/fork/patch/direct-storage path |
| Create/open | First create, identical retry, conflicting identity/request, missing/wrong catalog, schema mismatch, corrupt index state, migration, and cleanup failures |
| Revision | DAG, exact schema/dependency roots, projection semantic digest independent of physical repack, old revision interpretation, state digest, missing/corrupt root |
| Plan/commit | Binding mismatch, cross-database mutation, validation failure, cancellation, conflict, crash/unknown reconciliation, no partial candidate |
| Identity | Concurrent allocation/nonreuse and stable occurrence/spatial identity |
| Query | Native differential equivalence, semantic/physical binding verification, repack-stable result digest, keyset page concatenation, boundary no-gap/no-duplicate, unavailable projection rejection |
| Spatial | Conservative candidate, exact refinement, false positives, layer scope, stable entry identity |
| Change | Typed before/after reconstruction and arbitrary-diff separation |
| Dependency | Exact revision/content lock, wrong interface/schema/feature capability, immutable retention-contract identity, and location independence; mount availability belongs to Xcircuite integration tests |
| Retention/GC | Retain/release success, identical replay, claim/revision/generation conflict, authorization revocation, lost-response/restart reconciliation, claim nonreuse, atomic reachability-generation transition, named refs, releases, pending/active snapshot and query leases, receipts, runs, dependency pins, binding retirement, concurrent publication/targeted lease race, candidate-set deletion admission, first/middle/final delete-batch crash, restart-before-open intent reconstruction, partial-tree open rejection, continuous unrelated-reader liveness, stale candidates, and corrupt-intent repair failure |
| Concurrency/lifetime | Parallel reads, writer/readers, close races, cache eviction, owner/borrow lifetime, cleanup error observation |
| Service | Stable reconnect mapping of authenticated authority to validated opaque subject scope, canonical scope encoding/invalid decoding, exact snapshot, page backpressure, subject-scoped commit/reference/retain/release/status, cross-scope non-disclosure, caller-owned versus administrator reconciliation, disconnect, deadline, shutdown |
| Domain adapter | Domain↔database round trip, pure/full validator equivalence, cross-facet failure, facet migration |
| Compatibility | OpenDB OID/property/loss mapping and no direct canonical mutation |
| Portability | Fixed Native, WASM, and Embedded toolchain compile/link plus runtime paths where executable |
| Performance | Retained artifacts satisfying DDB-P01–P12 with correctness digests |

## Definition of Done

DesignDatabase is not production ready until:

- the framework-backed path is callable;
- at least one real domain vertical slice uses it end to end;
- Xcircuite can mount a write target and exact dependencies;
- success, failure, restart, reconciliation, retention, and close paths pass;
- real retained circuit workloads meet the approved budgets;
- standard export and Release evidence bind the exact dependency graph.
