# Development scope 02 — Persistent semantic memory MVP

## Status

Ready for implementation.

Scope 01 is implemented and remains the source-round-trip and managed-write
safety foundation. Its mechanics benchmark did not demonstrate authoring
efficiency, and model token counts were unavailable.

This scope tests the revised
[authoring-time semantic-memory hypothesis](../SEMANTIC_MEMORY.md). It must not
retrofit a favorable conclusion onto Scope 01.

## Outcome

Extend the current managed greenfield project so that 2Ravens:

1. Persists stable semantic entities, requested intent, derived relationships,
   evidence, source projections, and accepted operations in local SQLite.
2. Reuses that memory across independent CLI processes.
3. Detects source/database freshness before returning context or writing.
4. Rebuilds derived facts from managed source when the store is missing.
5. Never reconstructs missing intent by guessing.
6. Returns compact successful receipts by default.
7. Measures cumulative context across files-only, source-indexed, and
   semantic-memory lifecycle conditions.

This is a persistence and context-value experiment. It is not a performance
optimization, general repository indexer, or new programming language.

## Required demonstration

Starting from the existing Scope 01 application flow, create semantic memory:

```powershell
mix ravens init --root tmp/ravens_shop
```

Initialization creates or migrates:

```text
tmp/ravens_shop/.ravens/semantic.sqlite3
```

The database and its SQLite sidecar files are ignored through a local
`.ravens/.gitignore`. The existing management manifest remains separate.

Create a function with concise intent:

```powershell
@'
def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
'@ | mix ravens create function RavensShop.Pricing `
  --root tmp/ravens_shop `
  --intent "Calculate final price after the tier discount" `
  --stdin `
  --apply
```

Create a test with an intended target:

```powershell
@'
use ExUnit.Case, async: true

test "prices a VIP checkout" do
  assert RavensShop.Checkout.checkout(6_000, :vip) == 5_400
end
'@ | mix ravens create module RavensShop.PricingTest `
  --root tmp/ravens_shop `
  --test `
  --for function:RavensShop.Pricing.total/2 `
  --intent "Protect VIP checkout pricing" `
  --stdin `
  --apply
```

The default successful response is compact:

```text
ok operation:o7 revision:r3
added function:RavensShop.Pricing.total/2 entity:n8
derived calls:1 requested_intents:1
checks parse,round_trip,compile,test pass
```

Query persisted context in a fresh CLI process:

```powershell
mix ravens context function:RavensShop.Pricing.total/2 `
  --root tmp/ravens_shop `
  --include intent,callers,tests,evidence `
  --compact
```

Expected logical result:

```text
focus entity:n8 function:RavensShop.Pricing.total/2
intent requested "Calculate final price after the tier discount"
caller derived function:RavensShop.Checkout.checkout/2
test requested RavensShop.PricingTest intended_to_test
test derived RavensShop.PricingTest statically_related
test observed unknown reason=coverage_not_captured
freshness current revision:r3
```

Delete the database in a disposable test project and query again. 2Ravens must
rebuild derived source facts, assign explicit reconstructed identities, and
report requested intent as unavailable:

```text
intent unavailable reason=semantic_store_rebuilt_from_source
```

It must never silently recreate the prior intent from documentation or names.

## Fast-progress rule

Keep the current Scope 01 workflow passing while delivering these checkpoints:

1. Open SQLite and migrate an empty store.
2. Persist and read one stable node plus one intent.
3. Persist accepted source-derived edges and evidence.
4. Read compact context from the store in another process.
5. Detect stale source and reconcile derived facts.
6. Run the frozen lifecycle benchmark.

Do not begin with generic repository abstractions or a complete query engine.

## Product constraints

- Everything works locally and offline after dependency installation.
- Use SQLite as an embedded operational store, not an external service.
- Use `Exqlite` directly; do not introduce Ecto or a supervision tree.
- Keep one short-lived connection per public store operation in the MVP.
- Serialize writes; the CLI does not require concurrent writers.
- Source and Git remain recoverable authorities for implementation.
- The database is authoritative only for persisted semantic memory at its
  recorded revision.
- Requested, derived, and observed facts remain distinguishable in storage and
  output.
- All SQL uses bound parameters; never interpolate public input.
- Public APIs return `{:ok, value}` or `{:error, reason}`.
- Existing managed-path, stale-handle, qualification, and rollback protections
  remain intact.
- Successful CLI output is compact by default; diagnostics remain detailed on
  failure.

## Deliverables

### 1. SQLite dependency and storage boundary

Add the current compatible `Exqlite` `0.39` series as the only new production
dependency. Use the low-level SQLite API behind:

```elixir
TwoRavens.SemanticStore
TwoRavens.SemanticStore.SQLite
```

`SemanticStore` is the small public facade. No parsing, authoring, graph, or CLI
module calls `Exqlite` directly.

Acceptance:

- The project compiles and tests on Windows with the locked dependency.
- Opening a store creates no paths outside the validated `.ravens/` directory.
- Connections and statements close on success and failure.
- SQLite errors become structured errors without leaking full machine paths.

### 2. Versioned schema and migrations

Create idempotent forward-only migrations for this minimum schema:

```text
schema_migrations
semantic_revisions
semantic_nodes
source_projections
semantic_relations
semantic_intents
semantic_evidence
semantic_operations
```

Minimum responsibilities:

- `semantic_revisions`: working hash, optional Git revision, created time.
- `semantic_nodes`: stable opaque ID, kind, current semantic key, lifecycle.
- `source_projections`: node, managed path, range, content hash, fingerprint.
- `semantic_relations`: source, type, target, origin, confidence, revision.
- `semantic_intents`: subject, text, kind, operation, revision.
- `semantic_evidence`: subject, evidence type, status, origin, revision.
- `semantic_operations`: requested action, base revision, result, status.

Use foreign keys, uniqueness constraints, and indexes required by the exact
context demonstration. Do not add a generic property table or serialize the
entire graph into one blob.

Acceptance:

- Initialization and migration are repeatable.
- An unsupported newer schema fails closed.
- Partial migration failure leaves the prior schema usable or clearly failed.
- Duplicate stable IDs, semantic keys within one revision, and relation
  identities fail explicitly.

### 3. Semantic domain values

Add small immutable structs for:

- Stable entity ID
- Semantic revision
- Intent
- Typed semantic relation
- Evidence record
- Accepted operation

Keep stable entity identity separate from the mutable semantic key:

```text
entity:n8
function:RavensShop.Pricing.total/2
```

Generate bounded URL-safe entity and operation IDs without creating atoms from
input. Record semantic keys as strings.

Allowed origins are fixed domain values:

```text
requested
source_derived
compiler_confirmed
test_observed
runtime_observed
reconstructed
```

Do not encode origin or confidence as free-form prose.

### 4. Persist requested intent

Extend the ordinary Elixir APIs and Mix adapter with:

```text
intent: concise UTF-8 text
for: zero or more existing semantic targets for intended test relationships
```

Intent is optional for backward compatibility with the completed mechanics
benchmark. The lifecycle semantic-memory condition must supply it.

Validate length, encoding, duplicates, unknown targets, and option keys before
project access. Store an intended test relationship as origin `requested`; do
not present it as static or observed coverage.

Acceptance:

- Intent survives independent CLI processes.
- Intent is attached to the accepted entity and operation revision.
- A failed or dry-run candidate does not persist accepted intent.
- Repeating an operation cannot silently duplicate intent or relations.

### 5. Persist derived facts and evidence

After qualification and source read-back, persist the accepted graph facts
already produced by Scope 01:

- Modules, functions, clauses, comparisons, and tests
- Defines and calls relationships
- Static related-test relationships
- Source ranges, file hashes, and structural fingerprints
- Qualification evidence for the accepted operation

Do not store `test_observed` coverage merely because `mix test` passed. Store
the suite result as operation/revision evidence and leave per-function observed
coverage unknown.

Acceptance:

- The persisted derived graph has the same semantic signature as read-back
  source for the supported subset.
- Requested and derived relations may coexist without overwriting one another.
- Reconciliation replaces only derived facts for affected managed files.
- Evidence retains its producing revision and origin.

### 6. Cross-resource acceptance and recovery

Extend the existing immutable candidate pipeline:

```text
build semantic candidate
-> qualify source projection
-> verify base hashes
-> begin SQLite transaction
-> atomically materialize source and manifest
-> rebuild accepted source graph
-> persist semantic state
-> compare source and stored signatures
-> commit SQLite transaction
```

Snapshot affected source and manifest before writing. On any returned
post-write failure, roll back SQLite, restore source, and byte-verify recovery.

A process crash may leave source newer than semantic memory. The next open or
query detects the hash mismatch and enters reconciliation; it never returns
stale stored context as current.

Acceptance:

- Failed source writes persist no accepted semantic operation.
- Failed SQL writes restore source and manifest.
- Returned post-write errors prove rollback or return `:rollback_failed`.
- Crash-shaped stale state is detected on the next process.

### 7. Freshness and reconstruction

Implement two context paths:

```text
stored hashes current -> query semantic store
stored hashes stale   -> rebuild affected managed source -> reconcile derived facts
```

If the store is absent, initialize it and rebuild only source-derived facts.
Use origin `reconstructed`. Requested intent and intended relationships become
explicitly unavailable.

If stable identity reconciliation is ambiguous, preserve both candidates as
unresolved and refuse semantic writes against them.

Acceptance:

- Current store queries avoid full graph reconstruction.
- An external supported source edit updates derived facts and freshness.
- Unsupported or ambiguous edits mark affected facts unresolved.
- Missing intent is never synthesized.

### 8. Compact context and mutation receipts

Add a compact presentation mode and make it the default for successful
authoring operations. Preserve detailed output through an explicit `--details`
option and for failures.

Context materializes only requested fields. It reports:

- Stable ID and semantic key
- Requested intent when included
- Typed relations with origin
- Evidence with status and revision
- Freshness and unresolved frontier
- Output bytes

Acceptance:

- Default successful output omits full source and full diff.
- `--details` retains inspectable source, diff, and provenance.
- Compact output does not hide failed, unknown, or stale evidence.
- Tool-result bytes are recorded by integration tests.

### 9. Lifecycle benchmark contract

Add `benchmarks/semantic_memory/` with:

```text
README.md
tasks.exs
expected.exs
baseline.md
run.exs or an equivalent event recorder
```

Freeze three conditions:

1. `files_only`
2. `source_indexed`
3. `semantic_memory`

Freeze at least five sequential follow-up tasks against behaviorally equivalent
projects. Tasks must require intent, callers, test meaning, change impact, and
continued identity across a source movement or rename simulation.

The acceptance oracle stays outside the analyzed project. Record every
author-facing operation from events. Do not hardcode favorable counts.

### 10. Cumulative measurement and decision report

Record per task and cumulatively:

- Model tokens when exposed
- Tool-request and result bytes
- Context bytes supplied to the model
- Searches, listings, source reads, and semantic queries
- Stored facts reused
- Corrections and incorrect assumptions
- Required and forbidden fact recall
- Task correctness
- Wall time as diagnostic evidence

Publish an honest baseline even when semantic memory loses. The report must
separate:

- Creation overhead
- Cold-store reconstruction cost
- Warm semantic query cost
- Cumulative break-even, or absence of break-even
- Correctness differences

## Suggested code boundaries

```text
TwoRavens.SemanticStore                 public persistence facade
TwoRavens.SemanticStore.SQLite          Exqlite boundary and bound SQL
TwoRavens.SemanticStore.Migration       schema creation and version checks
TwoRavens.SemanticStore.Reconciliation  source/store freshness repair
TwoRavens.Semantic.Entity               stable identity
TwoRavens.Semantic.Intent               requested knowledge
TwoRavens.Semantic.Relation             typed relation and origin
TwoRavens.Semantic.Evidence             observed or derived evidence
TwoRavens.Semantic.Operation            accepted authoring operation
```

Do not move parser or graph logic into persistence modules. Convert domain
values at the store boundary. Keep `TwoRavens.Authoring`, `TwoRavens.Source`,
`TwoRavens.Context`, and the Mix task thin.

Run `mix xref graph --format cycles` after changing the dependency boundary and
remove every cycle.

## Checkpoints

1. **Store:** migrate SQLite and round-trip one domain entity.
2. **Intent:** persist function intent only after accepted apply.
3. **Facts:** persist derived graph facts and evidence without conflating origin.
4. **Context:** query intent and typed relations from a fresh process.
5. **Freshness:** detect drift and reconcile derived facts safely.
6. **Compactness:** replace verbose success output with bounded receipts.
7. **Lifecycle:** run the three frozen benchmark conditions.
8. **Decision:** report cumulative context break-even or failure honestly.

Each checkpoint leaves the existing Scope 01 tests passing.

## Out of scope

- Ecto or a repository abstraction framework
- Hosted, external, vector, or graph databases
- Concurrent writers or long-running store processes
- Database-as-source or generated code stored only in SQLite
- Committing SQLite files to Git
- Portable semantic export, branch merge, or synchronization
- General brownfield indexing
- Runtime function coverage
- MCP writes, UI, or a daemon
- New semantic edit verbs
- Full rename or move implementation outside the benchmark simulation
- Free-form SQL, Cypher, or database access for agents
- Wall-clock optimization beyond avoiding accidental repeated work

## Test strategy

Add focused tests for:

- Migrations, constraints, bound parameters, and schema-version rejection
- Stable IDs and semantic-key changes
- Requested, derived, observed, and reconstructed origins
- Intent persistence only after accepted operations
- Requested test intent versus derived static relationships
- Independent-process store reuse
- Missing-store reconstruction and explicit intent loss
- External source drift and ambiguous reconciliation
- SQL failure rollback with source byte restoration
- Compact response byte bounds and detailed opt-in output
- Lifecycle benchmark contract and event-derived metrics

All database tests use disposable validated project roots and close connections
before cleanup.

## Required verification

Keep noisy output in temporary logs and report one concise line per successful
command:

```powershell
mix format
mix compile --warnings-as-errors
$env:MIX_ENV = 'test'
mix compile --warnings-as-errors
mix test --no-compile
Remove-Item Env:MIX_ENV
mix credo --strict
mix dialyzer
mix sobelow --private
mix xref graph --format cycles
```

Also run:

- The complete Scope 01 greenfield workflow
- Fresh-process semantic-store context reconstruction
- Missing-store and stale-store recovery tests
- The three-condition lifecycle benchmark
- Documentation link and benchmark-contract checks

## Completion gate

The implementation scope is complete when:

- SQLite persists the minimum semantic schema locally and safely.
- Accepted operations preserve intent, derived facts, and evidence separately.
- Context reuses current stored facts in independent processes.
- Source drift is detected before context or mutation claims freshness.
- Missing stores rebuild derived facts without inventing intent.
- Successful tool output is compact and detailed evidence remains available.
- Scope 01 correctness and rollback guarantees still pass.
- The lifecycle benchmark is reproducible and publishes honest cumulative data.

Product expansion beyond this scope requires the additional decision gate in
[Authoring-time semantic memory](../SEMANTIC_MEMORY.md): the stored memory must
preserve unique useful facts and reach cumulative context break-even without
reducing correctness.
