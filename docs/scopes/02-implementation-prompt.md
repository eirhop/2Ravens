# Implementation prompt — Persistent semantic memory MVP

Copy the prompt below into a development task from the root of the 2Ravens
repository.

```text
Implement Scope 02 of the 2Ravens MVP in this repository.

Before changing code, read and follow completely:

1. AGENTS.md
2. .agents/skills/two-ravens-elixir-patterns/SKILL.md
3. docs/SEMANTIC_MEMORY.md
4. docs/scopes/02-semantic-memory-mvp.md
5. docs/ARCHITECTURE.md
6. docs/EDITING.md
7. docs/QUERY.md
8. benchmarks/greenfield_authoring/baseline.md

Treat docs/scopes/02-semantic-memory-mvp.md as the authoritative implementation
scope. Scope 01 is an implemented safety and source-round-trip foundation; do
not rewrite or reinterpret its unfavorable mechanics benchmark.

Goal

Add a small local SQLite semantic-memory layer that persists stable entities,
requested intent, derived facts, evidence, source projections, and accepted
operations across independent CLI processes. Use that store to return compact,
fresh context and implement the three-condition cumulative lifecycle benchmark.

The product hypothesis is not that SQLite makes initial file creation faster.
It is that authoring-time semantic memory preserves knowledge source indexing
cannot recover and reduces cumulative model context across later tasks.

Required implementation boundaries

- Add the current compatible Exqlite 0.39 series as the only production
  dependency; use it directly without Ecto.
- Keep Exqlite behind TwoRavens.SemanticStore and a focused SQLite adapter.
- Store the database under the validated .ravens directory and ignore SQLite
  database, WAL, and shared-memory files locally.
- Keep source and Git as recoverable implementation authorities.
- Keep stable entity ID separate from mutable semantic key.
- Preserve requested, source-derived, compiler-confirmed, test-observed,
  runtime-observed, and reconstructed origins as fixed domain values.
- Never accept derived calls or observed evidence as agent-authored truth.
- Never claim per-function observed test coverage merely because the suite
  passed.
- Persist accepted intent only after qualification and successful source
  materialization.
- Detect source/store hash drift before serving current context or writing.
- Rebuild derived facts when the database is missing, but report requested
  intent as unavailable instead of inferring it.
- Use bound SQL parameters for every public value.
- Serialize writes and use short-lived connections; do not add supervision.
- Keep public APIs consistent with {:ok, value} and {:error, reason}.
- Preserve every existing managed-path, stale-handle, qualification, atomic
  write, rollback, and graph/source round-trip guarantee.
- Make successful CLI output compact by default; keep full evidence behind
  --details and on failure.
- Do not add a graph database, Ecto, MCP writes, UI, daemon, brownfield import,
  portable sync, or new edit verbs.
- Do not stage, commit, or push unless explicitly asked.

Execution sequence

Implement checkpoint by checkpoint, leaving Scope 01 tests passing:

1. Add Exqlite and a versioned SQLite schema with migrations.
2. Round-trip one stable semantic entity through the store.
3. Capture function intent and requested test intent on accepted authoring
   operations.
4. Persist source-derived graph facts, projections, and qualification evidence
   without conflating origins.
5. Integrate SQLite transaction handling with existing source snapshots and
   rollback behavior.
6. Query current semantic memory from an independent CLI process.
7. Detect stale or missing stores and reconcile only derived facts.
8. Add compact success receipts and detailed opt-in output.
9. Add the frozen files-only, source-indexed, and semantic-memory lifecycle
   benchmark with event-derived cumulative metrics.
10. Publish the benchmark outcome honestly, including no break-even if that is
    the result.

Do not stop after schema or CRUD implementation. Reach the demonstrated flow in
the scope: author normal Elixir with concise intent, query persisted typed
context in a fresh process, reconstruct honestly after database loss, and run
the cumulative benchmark.

Implementation quality

- Keep semantic identity and evidence values below parsing, graph, authoring,
  persistence, and CLI layers.
- Keep parsers and graph assembly pure; persistence converts domain values at
  its boundary.
- Use schema constraints to reject duplicate identities rather than silently
  overwriting them.
- Bound intent size and validate UTF-8, option keys, duplicates, target
  existence, and value types before project access.
- Preserve exact provenance, revision, confidence, freshness, uncertainty, and
  frontier in APIs and output.
- Run mix xref graph --format cycles and remove every dependency cycle.

Verification

Run the complete verification in AGENTS.md and Scope 02. Keep noisy output in
temporary logs. Report concise evidence for formatting, dev/test compilation,
tests, Credo, Dialyzer, Sobelow, xref cycles, Scope 01 regression behavior,
SQLite migration and constraint tests, independent-process reuse, stale and
missing-store reconciliation, SQL/source rollback, compact output, and the
three-condition lifecycle benchmark.

Final report

Lead with whether the persistent semantic-memory demonstration works. Then
report:

- Public APIs, schema, and migration version
- New dependency and why it was necessary
- Requested, derived, and observed facts persisted
- Source/store consistency and recovery evidence
- Default and detailed context byte sizes
- Lifecycle benchmark results and cumulative break-even, if any
- Verification commands and outcomes
- Honest unsupported cases and remaining risks
- Exact diff scope and working-tree status

Do not claim model-token savings when host token counts are unavailable. Use
the defined byte metrics as fallback and label them accurately.
```
