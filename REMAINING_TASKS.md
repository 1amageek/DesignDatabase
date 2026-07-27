# DesignDatabase Remaining Tasks

The remaining implementation gaps are listed here. The current Native backend remains the safe reference oracle
while these are implemented.

| ID | Priority | Task | Completion evidence |
|---|---|---|---|
| DDB-R02 | P0 | Add domain adapter packages for canonical logical, technology, physical, parasitic, timing, DFT, photonic, and assembly facets | standard import/export round trips bound to exact revisions |
| DDB-R03 | P0 | Implement schema compiler and checked-in generated IDs/accessors/wire descriptors | reproducible generation and schema-diff fixtures |
| DDB-R04 | P1 | Implement immutable paged columns, string interning, variable arenas, and page checksums | differential corpus, sanitizer run, allocation/copy measurements |
| DDB-R05 | P1 | Replace full-image persistence with immutable content-addressed segments, checkpoints, recovery, and compaction | crash-boundary matrix and identity-preserving compaction tests |
| DDB-R06 | P1 | Add owned record batches and closure-scoped borrowed views | lifetime/non-escape tests and copy-count evidence |
| DDB-R07 | P1 | Add pagination and revision/query-bound continuations/change streams | resume mismatch, expiry, cancellation, and backpressure tests |
| DDB-R08 | P1 | Add external framed service transport and Swift/Python/Tcl clients | cross-process negotiation/query/mutation fixtures |
| DDB-R09 | P1 | Complete the implemented neutral OpenDB mapping with C ABI, `.odb` artifacts, stable OID retention, and a qualified corpus | OpenDB binary round-trip differential, OID scope, and loss-report fixtures |
| DDB-R10 | P1 | Add deterministic disjoint merge and typed semantic-conflict handoff | competing transaction corpus |
| DDB-R11 | P1 | Add CLI create/inspect/query/diff/verify/checkpoint/export | timeout-bounded end-to-end fixtures |
| DDB-R12 | P1 | Define and measure workloads against latency, throughput, memory, allocation, and copy budgets | retained benchmark artifacts, including comparable OpenDB workloads |
| DDB-R13 | P1 | Verify Native, WASM, and Embedded storage/isolation contracts | fixed toolchain compile/link plus executable target tests where possible |
