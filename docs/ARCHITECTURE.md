# Architecture

## Status

This document defines the shared architecture for the MVP experiments and the
three-phase product plan. It commits the project to a local deterministic
repository graph and a bounded embedded SQLite semantic-memory experiment, not
to an umbrella structure, hosted store, UI renderer, or runtime transport.

The repository is currently one Mix application and should remain simple until
validated workflows demonstrate boundaries that need independent ownership,
supervision, deployment, or replacement.

## Non-negotiable local operation

After installation, the complete core product must run with network access
disabled.

The architecture must not require:

- Accounts or API keys
- Cloud services
- Embedding models or learned rerankers
- Hosted vector or graph databases
- External database servers
- Mandatory Docker infrastructure
- Hidden telemetry or source uploads

Local keyword search, graph traversal, parsing, compilation evidence, test
capture, runtime capture, MCP, and the UI must all have local implementations.

## Conceptual responsibilities

```text
2Ravens
├── Munin — memory
│   ├── source and compiler fact production
│   ├── repository synchronization
│   ├── evidence and provenance
│   └── graph storage and retrieval
└── Hugin — thought
    ├── graph slicing
    ├── execution-envelope construction
    ├── context materialization
    ├── MCP
    ├── visualization
    └── review and debugging workflows
```

These names describe responsibilities. They are not application or process
boundaries until implementation experience proves that separation useful.

## System model

```text
Normal Elixir + intent ─→ authoring candidate ─→ managed source files
           │                       │                      │
           │                       └→ requested facts     │
           │                                              ↓
           └────────────────────────────────────→ fact producers
                                                          │
Source files / Git / compiler / tests / runtime ───────────┤
                                                          ↓
                                     embedded semantic memory
                                                          ↓
                                      deterministic graph slices
                                                          ↓
                                     CLI / MCP / review UI / explorer
```

The graph is built independently of a particular task. An agent interprets the
user's request and supplies explicit focus and traversal parameters to the
[context query](QUERY.md).

## Authority

```text
Source code = implementation authority
Git when present = named revision authority
File hashes = current working revision
Tests = behavioral evidence
Runtime sessions = observed evidence
Embedded database = operational semantic memory at one revision
Repository graph = source-derived and memory-enriched projection
```

2Ravens keeps a small versioned manifest of paths it created during the MVP;
that manifest grants write scope but does not duplicate source or graph facts.
2Ravens-specific code annotations and authoring macros are not part of the
architecture. Ordinary documentation, typespecs, behaviours, tests, routes,
callbacks, and other Elixir constructs are indexed because they are already
part of the system.

When a relationship cannot be derived, the graph records it as unresolved or
unknown rather than adding a duplicated declaration that can become stale.

## Persistent semantic memory experiment

Scope 02 stores stable entities, requested intent, derived relationships,
evidence, source projections, and accepted operations in local SQLite beneath
the validated `.ravens/` directory.

```text
requested knowledge ─┐
derived knowledge ───┼→ versioned semantic store → compact context
observed evidence ───┘
```

Use `Exqlite` directly behind `TwoRavens.SemanticStore`; do not add Ecto or
expose SQL to agents. The MVP uses short-lived connections and serialized CLI
writes. SQLite is selected only for this local experiment.

Requested, derived, and observed facts retain separate origins. Passing tests
provide revision evidence but do not establish per-function runtime coverage.
The complete hypothesis and evidence contract are in
[Authoring-time semantic memory](SEMANTIC_MEMORY.md).

The database is local operational state and is not committed to Git. If it is
missing, 2Ravens rebuilds source-derived facts and reports requested intent as
unavailable. Portable export and branch synchronization are deferred until the
lifecycle benchmark demonstrates value.

## Graph layers

The graph is more than a function call graph. It combines several connected
layers.

### Repository structure

Initial node types include:

- Repository revision
- Application
- Source file
- Module
- Function and macro
- Function clause
- Pattern and guard
- Behaviour, callback, and protocol
- Struct and type
- Test and doctest
- Documentation

### Control and data flow

Behavior requires more than knowing that one function calls another. The graph
should also represent:

- Conditional branches
- Clause and guard conditions
- Call sites
- Caller expressions mapped to callee arguments
- Call results mapped to local bindings and pattern matches
- Data dependencies between bindings
- Return shapes and exception paths when statically knowable
- Side-effect boundaries

### OTP structure

OTP relationships include:

- Supervisors and child specifications
- Processes and registered names
- GenServer callbacks
- Message shapes
- Send, call, and cast sites
- Message handlers
- State reads and writes where statically knowable
- Timers and background callbacks
- Links, monitors, and restart strategies

### Evidence

Evidence connects structural facts to their origin:

- Source parser
- Compiler tracer or metadata
- Static test relationship
- Observed test execution
- Observed runtime execution
- Git revision and change

## Nodes and stable identity

Node identifiers should survive irrelevant line movement where practical.

Examples:

```text
application:favn_core
module:Favn.Admission
function:Favn.Admission.admit/2
test:Favn.AdmissionTest:rejects_duplicate_run
```

Function identity begins with module, name, and arity. Clause identity also
needs file, clause position, and a structural fingerprint of its patterns and
guards. Runtime processes and events use session-scoped identities.

## Typed relationships

Likely relationships include:

- Defines
- Calls
- Invokes macro
- Expands to
- Data flows to
- Implements callback
- Implements protocol
- Uses struct or type
- Sends message
- Handles message
- Supervises
- Reads state
- Writes state
- Tested by
- Documented by
- Observed during
- Changed between revisions

Inverse relationships such as “called by” can be query projections rather than
separately stored facts.

### Call-edge detail

A call edge is not merely two function IDs. It should retain:

```text
Caller: Scheduler.submit/2
Callee: Admission.admit/2
Call site: scheduler.ex:42:5
Arguments:
  callee argument 1 ← request.run
  callee argument 2 ← state.capacity
Result:
  reservation ← call result
Path condition:
  request.status == :pending
Origin and confidence
Repository revision
```

Several calls between the same functions remain distinct call-site evidence.
A response may group them as one relationship with several locations without
discarding the distinction.

## Building the repository graph

The MVP read-back indexer parses only files listed in the management manifest
and produces per-file graph fragments for its supported Elixir subset. It
rebuilds this small graph on every CLI command.

Phase 1 broadens the same fragment boundary to every repository source file.
Once definitions are known, it resolves references and adds relationships until
the statically knowable graph reaches a fixed point.

External dependencies can initially terminate at boundary nodes. Dependency
source may be indexed later when a validated workflow requires traversal into
it.

### Source parsing

Elixir-native parsing provides the first graph without requiring successful
compilation. The MVP extracts the supported modules, functions, clauses,
patterns, guards, calls, tests, and exact source references from managed files.
Phase 1 later broadens extraction to macros, aliases, imports, behaviours,
documentation, types, and arbitrary repository files.

For invalid intermediate files, the first implementation may retain the last
valid fragment with explicit stale status. A tolerant parser is adopted only if
evaluation proves that this is insufficient.

### Compiler reconciliation

Compiler tracers, `mix xref`, expanded forms, and other compiler metadata may
confirm or enrich:

- Resolved local, remote, and imported calls
- Macro invocations and generated relationships
- Behaviours and protocols
- Struct expansion
- Compile-time dependencies
- Generated modules and functions

Compiler evidence retains its own revision and never silently overrides newer
source-derived evidence.

### Macros

Macros need two connected representations:

```text
Source function --INVOKES_MACRO--> Macro
Generated function --CALLS--> Another function
```

This preserves what the developer wrote and what compilation produced.
Compile-time and runtime relationships must remain distinguishable.

### Dynamic calls

Elixir relationships may depend on runtime values:

- `apply/3`
- Anonymous functions passed through higher-order code
- Protocol implementations selected from runtime types
- Dynamically constructed module names
- Generated code unavailable before compilation
- Dynamic process destinations

These become first-class candidate or unresolved edges:

```text
Dynamic call
Possible targets: [...]
Resolution: incomplete
Reason: module determined at runtime
```

Test and runtime observations may later confirm one target without erasing the
remaining static possibilities.

## OTP relationship resolution

A normal call graph does not connect a message send to its handler:

```elixir
GenServer.call(Scheduler, {:submit, run})
```

```elixir
def handle_call({:submit, run}, _from, state) do
  # ...
end
```

The graph should represent:

```text
Caller
--SENDS {:submit, run}-->
Message shape
--HANDLED_BY-->
Scheduler.handle_call/3 clause
```

Registered names, module references, child specifications, supervisors, and
known process identities help resolve the destination. Values in the message
map to variables in the handler pattern. Ambiguous destinations remain
candidate edges.

## Execution envelope

The repository graph is the static supergraph. An execution envelope is an
input-sensitive graph slice describing everything that could execute from one
or more focus nodes under known constraints.

```text
Focus + abstract inputs
→ match possible clauses
→ evaluate supported guards and branches
→ map arguments into callees
→ follow possible calls and messages
→ stop, merge, or continue according to the query
```

### Abstract values

2Ravens does not execute arbitrary application code to construct the envelope.
It reasons over safe abstract values:

- Unknown
- Known literal
- Struct or map shape
- Possible atom set
- Numeric range
- Tuple shape
- Known keys

Patterns, standard guards, and supported expressions can narrow those values.
An unknown expression keeps every compatible branch possible.

### Control and data dependencies

A call graph answers which functions may call which other functions. A program
dependence graph also answers which conditions and values influence a call or
effect.

The implementation should grow in this order:

1. Function and clause call graph
2. Call-site argument and result mapping
3. Intra-function control and data dependencies
4. Interprocedural forward and backward slices
5. OTP message and state-flow slices

### Cycles and path growth

Recursion and mutually dependent functions form cycles. They should be
represented once, for example as strongly connected components, rather than
expanded indefinitely.

Path explosion is bounded by query depth, node limits, abstract-state merging,
and meaningful stopping points. Bounded analysis must disclose its unexpanded
frontier.

## Graph slicing

The useful result is normally a minimal explanatory subgraph, not every node
within a radius.

Important path forms include:

- Public entry point → focus
- Focus → side effect
- Test → focus
- Sender → message → handler
- Handler → state transition
- Focus → application or external boundary

Deterministic graph techniques may include:

- Shortest meaningful paths
- Forward and backward program slices
- Strongly connected component collapsing
- Dominators or nodes shared by all relevant paths
- Boundary and effect termination
- Collapsing generic helper chains
- Explicit frontier reporting

No learned reranker is required.

## Multi-focus slicing

For several focus nodes, Hugin performs multi-source traversal:

1. Build reachability and distance maps for each focus.
2. Find common upstream and downstream nodes.
3. Find meaningful paths connecting the focuses.
4. Build one deduplicated union of the required paths.
5. Separate shared and focus-specific regions.
6. Materialize each source range and document once.

Shared nodes gain value because they explain several focuses, but common
standard-library utilities and unrelated high-fan-in helpers should be
collapsed. If the focuses are disconnected within the limits, the response
returns separate components.

The public behavior is defined in [Context query](QUERY.md).

## Evidence, confidence, and provenance

The same relationship may have several evidence records:

```text
Admission.admit/2 --CALLS--> RunStore.insert/1
├── source parser: probable
├── compiler: confirmed
├── test session: observed
└── runtime session: observed
```

Every evidence record should identify:

- Origin
- Confidence
- Source range or runtime event
- File revision or session identifier
- Capture or indexing time where relevant
- Normalization or redaction applied

Relevance and confidence are different. A probable direct relationship may be
more important to show than a confirmed distant utility call.

## Freshness

Every response must report:

- Repository revision
- Working-tree state
- Files indexed successfully
- Files with stale or incomplete fragments
- Compiler evidence that is current or stale
- Unresolved dynamic relationships
- Analysis limits and unexpanded frontier

Uncertainty is part of the graph domain, not presentation metadata added later.

## Repository perspectives

The system needs three related perspectives:

- **Base graph:** selected Git base or commit
- **Working graph:** current files, including uncommitted edits
- **Change projection:** added, removed, or modified nodes, relationships,
  conditions, and evidence

Phase 1 needs revision awareness for correct context. Phase 2 turns graph and
execution-envelope differences into the review product.

## Source materialization

The graph stores relationships and references to source ranges. Exact source is
read from the relevant revision only when a query requests it.

Before returning source, 2Ravens must verify the revision or file hash. It must
never combine relationships from one revision with source from another without
marking that mismatch.

Multi-focus responses materialize shared source and documentation once and
reference it from every relevant path.

## Semantic authoring and candidate changes

Semantic authoring creates the first graph identities and then reuses them
without changing the authority model:

```text
Large creation: normal Elixir fragment ─────────┐
Small change: context -> edit handle -> set ────┤
                                                 ↓
candidate graph and source patch
-> source-to-graph round-trip
-> isolated compile and focused checks
-> explicit apply
-> working-tree source
-> re-indexed graph
-> accepted semantic-memory transaction
```

An edit handle is a compact revision-bound alias for one canonical graph node,
its source anchor, structural fingerprint, and permitted editable properties.
It is rejected when the base revision, file hash, or structure is stale.

A candidate is immutable and unapplied. It records requested operations,
resolved targets, source and graph deltas, affected execution envelopes,
qualification evidence, and diagnostics. Scope 03 persists versioned temporary
drafts so correcting one entity creates a new draft version without resending
the original large request. This is cached state, never a long-running SQL
transaction.

Operations never write graph storage records directly. Free-form ordinary
Elixir may create only entirely new modules. Existing code is changed through
exact module-child, function, clause, or module-form targets; there is no
whole-existing-module merge or implicit deletion. Parsing, compiler
reconciliation, and tests continue to derive relationships and evidence.

Before apply, 2Ravens materializes the candidate source, rebuilds affected graph
fragments, and compares that rebuilt graph with the candidate graph. A mismatch
is an error, not an automatic repair. Apply verifies the base hashes, writes the
ordinary source patch, re-indexes the result, and persists accepted semantic
facts transactionally with compensating source rollback. It does not commit to
Git.

The complete contract and MVP plan are in [Semantic editing](EDITING.md).

## Index updates

Scope 01 explicitly rebuilds managed per-file fragments for each command. Scope
02 first verifies stored file hashes. Current stores serve context directly;
stale stores rebuild affected managed fragments and reconcile only derived
facts. Once Phase 1 requires continuous updates, use the same fragment boundary:

```text
File event
→ debounce and content hash
→ parse file fragment
→ atomically replace prior fragment
→ mark compiler evidence stale
→ update affected relationships and slices
```

An invalid update must not destroy the last known valid fragment without making
the loss visible.

## Interfaces

The core operation belongs to an ordinary Elixir API. Transports remain thin:

```text
mix ravens context ─┐
local MCP context ──┼→ TwoRavens.Context → semantic store + Munin graph
future local UI ────┘

mix ravens create/set [--apply] → TwoRavens.Authoring → candidate → source patch
```

The Mix task is useful for development, diagnostics, scripting, and fallback.
The local STDIO MCP server is the preferred context integration because it
provides a discoverable structured schema and can keep the index warm. The
semantic-authoring MVP is CLI-first; an MCP write adapter is added only after
the ordinary Elixir authoring API and CLI contract are validated.

MCP is a transport, not the domain architecture.

## Architecture by phase

### MVP foundation — managed semantic authoring

- Initialize a small manifest in an existing greenfield Mix project.
- Create modules and functions from ordinary Elixir.
- Rebuild a narrow graph from only managed files on every command.
- Query created behavior and apply one revision-bound semantic edit.
- Qualify every applied candidate through source round-trip, compilation, and
  tests.

### MVP foundation — persistent semantic memory

- Persist stable entities, requested intent, derived facts, and evidence.
- Reuse current memory across independent CLI processes.
- Reconcile stale or missing stores without inventing intent.
- Return compact context and mutation receipts.
- Compare cumulative context across files, source indexing, and semantic memory.

### Phase 1 — possible behavior

- Build the local repository supergraph.
- Construct deterministic single-focus and multi-focus slices.
- Narrow paths using optional abstract input constraints.
- Expose one context operation through Mix and MCP.

### Phase 2 — changed possibilities

- Compare base and working graphs.
- Compare execution envelopes and their evidence.
- Render changed paths, clauses, messages, effects, tests, and uncertainty.

### Phase 3 — observed behavior

- Capture one explicit bounded local execution.
- Attach observed function, message, process, and state events to graph nodes.
- Highlight the actual trace inside the possible envelope.
- Replay the captured evidence without claiming unsupported causality.

## Current implementation direction

Scope 01 implemented:

- One Mix application
- Small modules separated by explicit data contracts
- Safe root validation and a small manifest of managed paths
- Normal Elixir input for module and function creation
- Elixir-native parsing of the supported managed-source subset
- In-memory immutable graph structures rebuilt on each command
- One focused context API
- `mix ravens` as the first adapter
- CLI-first creation, candidate qualification, context, `set`, and `--apply`
- Disposable greenfield-project integration tests

Scope 02 implemented:

- One local SQLite file beneath `.ravens/`
- `Exqlite` behind a small semantic-store boundary without Ecto
- Versioned migrations and constrained relational tables
- Stable entity IDs separate from semantic keys
- Requested intent and intended-test relationships
- Persisted derived facts and qualification evidence with explicit origins
- Source/store freshness and reconciliation
- Compact success output
- A three-condition cumulative lifecycle benchmark

Scope 03 next adds ordered entity operations, versioned repairable drafts,
multi-module creation input, clause child editing, and one JSON-shaped transport
handler while retaining managed-source boundaries.

Phase 1 later adds general repository indexing, compiler reconciliation, the
complete context query, real-repository benchmarks, and one local STDIO MCP
adapter. Continuous watching, tolerant parsing, alternative embedded stores,
and portable semantic synchronization remain evidence-driven choices.

## Decisions intentionally deferred

- Umbrella application boundaries
- Tolerant incomplete-source parser
- Production graph visualization library
- Runtime-agent transport and isolation model
- Distributed runtime observation
- Production observation
- A full MCP server and plugin packaging
- Portable or multi-writer draft storage
- Portable semantic-memory export, merge, and synchronization
- Alternative embedded storage technology
- General brownfield importing during the managed entity-authoring MVP

All future choices must preserve local operation and inspectable results.

## Architectural principles

1. Build the repository graph independently of a user task.
2. Preserve ordinary source documentation and accepted operation history with
   provenance; derive structural and behavioral relationships from code and
   evidence rather than custom annotations.
3. Source and Git when present remain authoritative; tests and runtime provide
   evidence.
4. Every fact has inspectable provenance, confidence, revision, and freshness.
5. Statically unknowable relationships remain candidate, unresolved, or
   unknown.
6. Preserve control, data, message, and effect paths—not only call adjacency.
7. Graph queries are explicit, deterministic, bounded, and progressively
   expandable.
8. Multi-focus context is combined and deduplicated before source
   materialization.
9. Human and AI products share one graph and evidence model.
10. Every core capability runs locally without credentials or hosted services.
11. A semantic candidate becomes trustworthy only after its materialized source
    rebuilds to the proposed graph without hidden changes.
