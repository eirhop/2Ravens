Architecture

Overview

2Ravens is an Elixir umbrella application with two conceptual components:

TwoRavens
├── Munin — memory
└── Hugin — thought

Munin

Munin continuously observes and indexes the codebase.

Responsibilities:

* Source indexing
* Working-tree synchronization
* Compiler reconciliation
* Test evidence
* Runtime trace ingestion
* Graph storage
* Provenance
* Query primitives

Hugin

Hugin turns indexed facts into useful understanding.

Responsibilities:

* MCP server
* Context selection and compression
* Change-impact analysis
* Flow projection
* Human-facing visualization
* Copy-context generation
* Review workflows

This is a conceptual separation. The final umbrella may contain more than two OTP applications.

⸻

Proposed umbrella structure

apps/
├── two_ravens_core
├── munin_index
├── munin_store
├── munin_source
├── munin_compiler
├── munin_tests
├── munin_runtime
├── hugin_query
├── hugin_context
├── hugin_mcp
└── hugin_view

The exact number of applications should remain small initially. Boundaries should only be introduced where they provide genuine isolation or reusable contracts.

A simpler first structure may be:

apps/
├── munin
├── hugin
├── two_ravens_mcp
└── two_ravens_view

⸻

System architecture

Source files
Git working tree
Compiler metadata
ExUnit execution
Runtime traces
       ↓
Fact producers
       ↓
Munin graph index
       ↓
Graph query and projection
       ↓
Hugin
  ├── MCP
  ├── Review UI
  └── Context export

⸻

Graph model

The graph stores relationships and retrieval metadata, not full canonical copies of source files.

Example function node

id: function:Favn.Admission.admit/2
module: Favn.Admission
name: admit
arity: 2
file: apps/favn_core/lib/favn/admission.ex
line_start: 42
line_end: 78
visibility: public

Example edge

from: function:Favn.Orchestrator.submit/2
type: CALLS
to: function:Favn.Admission.admit/2
origin: source
confidence: probable
file_revision: sha256:...
source_range: 61:5-61:38

Evidence model

The same relationship may have multiple evidence records:

CALLS edge
├── source parser: probable
├── compiler tracer: confirmed
├── test trace: observed
└── runtime trace: observed

Evidence should be combined without discarding provenance.

⸻

Storage

The graph index is derived and disposable.

Source code = authority
Tests = behavioral evidence
Runtime = observed evidence
Graph index = regenerable projection

SurrealDB option

An embedded SurrealDB Rust engine is a possible fit because the project requires:

* Graph traversal
* Document-like metadata
* Tabular trace sessions
* Full-text search
* Potential vector search

Possible deployment:

Elixir process
→ Rustler boundary
→ embedded SurrealDB
→ in-memory store

The graph should store compact metadata and references to source ranges. Exact source is read from disk when constructing context.

NIF isolation

A Rustler NIF executes within the BEAM operating-system process.

Therefore:

* Long operations must not block normal schedulers.
* Queries should run on dirty schedulers or a Rust worker pool.
* Inputs and outputs must be bounded.
* Native crashes remain capable of terminating the VM.

If stronger fault isolation becomes necessary, the storage engine can run as a separate executable behind an Erlang Port.

Storage abstraction

The domain must not depend directly on SurrealQL.

defmodule TwoRavens.GraphStore do
  @callback replace_file_fragment(fragment()) ::
              :ok | {:error, term()}
  @callback traverse(query()) ::
              {:ok, graph_result()} | {:error, term()}
  @callback affected_subgraph(changes(), options()) ::
              {:ok, graph_result()} | {:error, term()}
end

This permits alternative implementations such as SQLite or an ETS-based prototype.

⸻

Continuous indexing

Compilation is not the primary update trigger.

Source indexing pipeline

Filesystem event
→ change coalescer
→ content hashing
→ tolerant parser
→ file graph fragment
→ atomic graph replacement
→ impact recalculation

File fragment ownership

Every source-derived fact belongs to a specific file revision.

Replacing a file fragment must:

1. Remove facts owned only by the previous revision.
2. Insert facts from the new revision.
3. Preserve evidence from tests or runtime when still referentially valid.
4. Mark compiler-confirmed facts stale until reconciliation.

Parser layers

Tolerant parser

Used immediately after edits.

Extracts:

* Modules
* Functions
* Clauses
* Patterns
* Guards
* Explicit remote calls
* Aliases
* Imports
* Behaviours
* GenServer callbacks
* Test definitions

Tree-sitter is a likely option because it can retain useful structure from incomplete files.

Elixir AST parser

Used when the file parses successfully through Elixir.

Code.string_to_quoted(source, columns: true)

Provides richer Elixir-specific AST information.

Compiler reconciliation

Used after compilation.

Confirms or enriches:

* Resolved imports
* Macro expansion
* Generated functions
* Module dependencies
* Behaviours
* Protocols
* Compiler-observed calls

⸻

Git graph overlays

2Ravens maintains multiple graph perspectives:

HEAD graph
Working-tree graph
Change graph

HEAD graph

Represents the checked-out base commit.

Working-tree graph

Represents current files, including uncommitted edits.

Change graph

Represents added, removed or modified symbols and relationships.

This allows queries such as:

* What behavior changed?
* Which flows existed before?
* Which new callers were introduced?
* Which tests no longer traverse a branch?
* Which process state transitions changed?

⸻

Test instrumentation

Tests provide behavioral evidence.

A test capture session should produce:

test
→ functions entered
→ clauses matched
→ guards evaluated
→ calls observed
→ values normalized
→ messages sent
→ process state transitions
→ assertions

Clause identification

Function clauses need stable identifiers based on:

* Module
* Function
* Arity
* Source file
* Clause position
* Pattern fingerprint

Line numbers alone are insufficient because they shift frequently.

Values

Runtime values may be large or sensitive.

Stored examples should support:

* Redaction
* Depth limits
* Collection-size limits
* Struct-aware normalization
* Hashing
* Optional raw-value retention for local sessions

⸻

Runtime attachment

Runtime attachment is an optional development/test feature.

Runtime agent

The target application includes an optional dependency or starts an attached helper process.

Target BEAM
├── application processes
└── TwoRavens.RuntimeAgent

The runtime agent emits structured events to the TwoRavens UI or trace collector.

Event sources

Possible sources include:

* Telemetry
* Erlang trace sessions
* :sys debugging events
* Process monitoring
* Supervisor introspection
* Logger metadata
* Explicit TwoRavens instrumentation

Scoped sessions

Each trace session defines:

* Trigger
* Process scope
* Module scope
* Correlation metadata
* Maximum duration
* Maximum event count
* Value capture policy
* Redaction policy

Causality

Asynchronous systems do not always have a simple call stack.

2Ravens should distinguish:

* Confirmed synchronous parent/child relationships
* Message send and receive relationships
* Temporal correlation
* Inferred causality
* Unknown causality

The UI must not present inferred causality as certain.

⸻

Process and state model

Process nodes

Runtime process nodes may contain:

* PID
* Registered name
* Initial call
* Current function
* Supervisor parent
* Children
* Links
* Monitors
* Mailbox length
* Restart count
* Start and stop time

GenServer transitions

Represent each callback as:

Incoming message
+ old state
→ callback clause
→ reply or action
+ outgoing messages
+ new state

State diffs should be structural and field-oriented where possible.

⸻

Query architecture

Raw graph traversal is insufficient for users and AI.

Hugin provides opinionated projections.

Example projections

* symbol_context
* change_context
* execution_flow
* behavior_tree
* test_coverage
* process_context
* architecture_context
* runtime_session

Task-aware ranking

Rank candidates using signals such as:

* Changed symbol
* Graph distance
* Entry-point relevance
* Public API visibility
* Side-effect importance
* Process boundary crossing
* Test evidence
* Runtime evidence
* Documentation
* Historical co-change
* Token cost

⸻

MCP response construction

MCP context generation has three stages:

Graph retrieval
→ relevance ranking
→ source materialization

Graph retrieval

Select candidate symbols, tests, processes and flows.

Relevance ranking

Remove or summarize low-value nodes.

Source materialization

Read exact source ranges from the current working tree.

The graph database should not be trusted as the canonical source text.

Response structure

Summary
Index freshness
Behavior and flow
Changed symbols
Relevant source
Tests and examples
State and side effects
Architecture constraints
Uncertainties

⸻

Visualization architecture

The UI should visualize graph projections, not the raw complete graph.

Likely technologies:

* Phoenix LiveView
* SVG or Canvas graph renderer
* Server-side graph query and layout preparation
* Client-side pan, zoom and drill-down

Progressive disclosure

The server returns graph levels based on user intent:

Domain flow
→ module/function flow
→ clause flow
→ runtime detail

The UI must avoid rendering every node simultaneously.

⸻

Security

Runtime data may contain:

* Credentials
* Personal information
* Database records
* Authentication tokens
* File paths
* Business-sensitive state

Required controls include:

* Development/test only by default
* Explicit runtime attachment
* Local binding by default
* Authentication
* Redaction rules
* Value depth and size limits
* Network allow-lists
* Trace session limits
* No production credentials in manual workbench runners

⸻

Performance constraints

The tool must avoid materially changing application behavior.

Important rules:

* No unrestricted global function tracing by default
* Bounded trace sessions
* Bounded event queues
* Backpressure
* Sampling or dropping policies
* Asynchronous ingestion
* Incremental graph updates
* Cached graph projections
* Source reads only when needed

Runtime observation that changes timing can create misleading results. The UI should disclose tracing mode and overhead risk.

⸻

Architectural principles

1. Source code remains authoritative.
2. Every graph fact has provenance.
3. Provisional and confirmed facts are distinguishable.
4. Index updates are incremental.
5. Compiler data enriches rather than gates indexing.
6. Runtime tracing is scoped and bounded.
7. Graph projections are task-oriented.
8. Storage is replaceable.
9. Human and AI interfaces share the same graph.
10. Uncertainty must be visible.