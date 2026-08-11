# DesignDatabase Portability Matrix

Updated: 2026-08-11

This matrix fixes the supported product/profile combinations. An unsupported profile
does not select another backend or weaken ownership, synchronization, validation, or
shutdown semantics.

| Product / profile | Native macOS | WASI | Embedded WASI | Contract |
|---|---|---|---|---|
| `DesignDatabaseCore`, default traits | Supported | Not qualified | Unsupported | Host `Codable` contract through `FoundationSerialization` |
| `DesignDatabaseCore`, no default traits | Runtime verified | Runtime verified | Runtime verified | Portable values, validation, ordering, identity, and protocol contracts |
| `DesignDatabaseNative` | Behaviorally verified | Unsupported profile | Unsupported profile | In-memory reference oracle with host digest/serialization adapters |
| `DesignDatabasePersistence` | Behaviorally verified | Unsupported profile | Unsupported profile | Darwin file owner, lock, WAL, sync, and fallible close |
| `DesignDatabaseRuntime` | Behaviorally verified | Unsupported profile | Unsupported profile | Fixed public database-framework host runtime |
| `DesignDatabaseService` | Behaviorally verified | Unsupported profile | Unsupported profile | Host wire/session/process transport contract |

## Fixed toolchain evidence

The following commands use the pinned Swift 6.4 snapshot and matching SDK identifiers:

```bash
swift run --disable-default-traits DesignDatabaseCorePortabilityProbe -j 4
swift run --disable-default-traits \
  --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm \
  DesignDatabaseCorePortabilityProbe -j 4
swift run --disable-default-traits \
  --swift-sdk swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a_wasm-embedded \
  DesignDatabaseEmbeddedCorePortabilityProbe -j 4
```

All three compile, link, and run with this exact output:

```text
DesignDatabaseCorePortabilityProbe:lsi:portability.core:agent-operation:candidate/main:key4:proposeCandidate,read
```

The probe executes canonical locator and token validation, canonical key validation,
integer-bound containment/intersection, and deterministic authorization-grant
canonicalization. The first WASI execution exposed a runtime metadata trap in
`Set`-based grant canonicalization; the implementation now uses deterministic
sort-and-adjacent-deduplication, and the existing host serialization/deduplication test
passes.

## Host behavior evidence

| Product | Direct behavior |
|---|---|
| Native | Exact immutable candidate plus separate named-reference CAS |
| Persistence | WAL-backed promoted revision reopen |
| Runtime | Atomic replayable candidate commit that leaves `main` unchanged |
| Service | Disconnect followed by exact operation reconciliation after reconnect |
| Composition | Nine P0 adapters compile in Xcircuite; both generic sky130A lineages and the real child-process database session pass |

The portable Core profile removes codec declarations at compile time. It does not
return placeholder data, emulate a digest backend, or silently select a host product.
