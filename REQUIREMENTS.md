# DesignDatabase Requirements

Status: tracked per requirement. “Implemented” means a callable success and failure path is covered by focused
tests; “Partial” means a safe reference path exists but the complete storage, service, portability, or evidence
contract is not yet met.

## Implementation Status

| Requirement | Status | Current evidence / remaining boundary |
|---|---|---|
| DDB-001–007 | Implemented | Separate products, multiple instances, exact immutable revisions, noncopyable transaction, scoped IDs, strict resolution, domain-neutral schemas |
| DDB-008 | Implemented | Required/type/relation-target/facet checks, sparse composite uniqueness constraints, deterministic typed conflicts, and injected validators have success/failure coverage |
| DDB-009 | Implemented (reference) | Immutable entity, facet, name, hierarchy, connectivity, spatial, cross-facet, change, and dependency indexes; optimized storage representation remains P1 |
| DDB-010 | Implemented | Canonically sorted change sets and digests, including reopen-time differential validation |
| DDB-011 | Partial | Durable checksummed full-image WAL and recovery exist; immutable segments, checkpoints, and compaction do not |
| DDB-012–014 | Implemented (local) | Fail-closed corruption validation, CAS references, schema/capability negotiation, monotonic in-process session lease |
| DDB-015 | Not implemented | Domain import/export adapters are separate future packages |
| DDB-016 | Implemented | Core/Native contain no OpenDB/OpenROAD dependency; pure compatibility targets depend inward on Core |
| DDB-017 | Not implemented | Schema compiler and generated accessors/descriptors are absent |
| DDB-101 | Implemented (reference) | Opened snapshots are immutable synchronous values and cached by exact revision |
| DDB-102–110 | Partial | DDB-109 neutral mapping is implemented; paged/zero-copy/remote/pagination/merge/compaction/CLI, OpenDB binary artifacts, and DDB-110 external client remain |
| DDB-111 | Implemented (reference) | Query explain reports selected index and scan estimate; unavailable indexes reject unless full scan is explicitly admitted |

## P0 Functional Requirements

| ID | Requirement |
|---|---|
| DDB-001 | Depend on `CircuiteFoundation` and no domain package in Core / Native products. |
| DDB-002 | Create and open multiple independent database instances without global mutable state. |
| DDB-003 | Expose immutable exact-revision read snapshots. |
| DDB-004 | Execute task-owned transactions that atomically publish candidate revisions or publish nothing. |
| DDB-005 | Allocate nonzero database-scoped entity IDs that are never reused. |
| DDB-006 | Resolve exact entity references and reject database, revision, facet, and kind mismatches. |
| DDB-007 | Register versioned facet schemas without teaching Core domain semantics. |
| DDB-008 | Validate field, relation, uniqueness, and adapter-provided semantic constraints before commit. |
| DDB-009 | Maintain entity, facet, name, hierarchy, connectivity, spatial, cross-facet, change, and dependency indexes. |
| DDB-010 | Produce canonical deterministic change sets between revisions. |
| DDB-011 | Persist immutable segments, revision manifests, WAL, and named references with crash recovery. |
| DDB-012 | Detect corruption and fail without returning partial successful data. |
| DDB-013 | Provide atomic compare-and-set named-reference updates without owning approval policy. |
| DDB-014 | Provide explicit schema and capability negotiation for in-process and service clients. |
| DDB-015 | Keep standard import / export in domain adapter packages and bind every result to an exact revision. |
| DDB-016 | Isolate OpenDB compatibility and OpenROAD algorithms from Core and Native products. |
| DDB-017 | Validate checked-in facet schemas and generate stable typed IDs, accessors, storage descriptors, wire descriptors, and schema-diff evidence. |

## P1 Functional Requirements

| ID | Requirement |
|---|---|
| DDB-101 | Provide lock-free immutable reads after snapshot acquisition. |
| DDB-102 | Provide paged column storage with interned strings and immutable variable-length segments. |
| DDB-103 | Provide closure-scoped zero-copy borrowed batches and owned cross-task batches. |
| DDB-104 | Provide local memory-mapped and remote streaming data planes with identical query semantics. |
| DDB-105 | Provide pagination and resumable change streams bound to exact revision and query identity. |
| DDB-106 | Provide deterministic disjoint-change merge and structured semantic conflict handoff. |
| DDB-107 | Provide checkpoint, compaction, and storage accounting without changing logical identity. |
| DDB-108 | Provide CLI create, inspect, query, diff, verify, checkpoint, and export operations. |
| DDB-109 | Provide OpenDB artifact, OID, object, and property mapping with structured loss reports. |
| DDB-110 | Provide an OpenDB-style external client surface without using OpenDB binary layout internally. |
| DDB-111 | Provide structured query explain evidence and reject an unapproved full-scan plan. |

## Correctness Requirements

| ID | Requirement |
|---|---|
| DDB-C01 | No incomplete or unsupported operation returns an empty success value. |
| DDB-C02 | No native failure silently switches to an external backend. |
| DDB-C03 | A revision never observes partially persisted segments or partially updated indexes. |
| DDB-C04 | Query ordering is explicit whenever results are persisted, hashed, or paginated. |
| DDB-C05 | Full scans occur only when the query execution policy permits them. |
| DDB-C06 | Snapshot, transaction, batch, and pointer lifetimes are enforced by safe owners / leases. |
| DDB-C07 | Native, WASM, and Embedded use the same logical `Mutex<State>` / actor isolation contract. |
| DDB-C08 | Approval, qualification, and release status cannot be synthesized by database APIs. |

## Performance Requirements

| ID | Requirement |
|---|---|
| DDB-P01 | Define workload, input scale, latency / throughput, allocation, copy, and memory budgets before optimization. |
| DDB-P02 | Benchmark entity, hierarchy, connectivity, spatial, transaction, diff, save / restore, and service paths. |
| DDB-P03 | Compare semantically equivalent physical-design workloads with OpenDB where possible. |
| DDB-P04 | Do not accept unsafe implementation solely because it compiles or uses pointers. |
| DDB-P05 | Record allocation / copy counts or equivalent measurements for every claimed zero-copy path. |

## Verification Requirements

| Area | Required evidence |
|---|---|
| Reference model | Native storage and query results match a safe reference implementation |
| Transaction | commit, abort, cancel, conflict, validation failure, retry, and read-your-writes tests |
| Concurrency | concurrent snapshot reads, parallel candidate commits, and close / commit / stream races |
| Persistence | crash at every publication boundary, truncated WAL, missing segment, and checksum mismatch |
| Query | indexed result equals full reference scan for entity, hierarchy, connectivity, spatial, and change |
| Lifetime | lease release, owner close, stale handle, and pointer non-escape tests |
| Compatibility | OpenDB round trip, OID scoping, unknown property, unsupported domain, and loss-report tests |
| Portability | native macOS, normal WASM, and Embedded WASM compile / link and executable runtime paths where supported |
| Sanitizers | Address, Thread, and Undefined Behavior sanitizer runs for supported host targets |
| Performance | retained before / after benchmark artifacts with workload and hardware identity |

## Definition of Done

No requirement is complete from declarations, generated schema, build success, or benchmark speed alone. Completion
requires working success and failure paths, deterministic artifacts, focused timeout-bounded tests, documentation,
and evidence that the owning responsibility is not duplicated in Foundation, Xcircuite, or a domain Engine.
