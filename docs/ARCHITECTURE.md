# Architecture

## Status

This document defines the shared architectural direction for the product plan.
It does not commit the project to an umbrella structure, graph database, native
extension, UI renderer, or runtime transport.

The repository is currently one Mix application. It should remain simple until
validated workflows demonstrate boundaries that need independent ownership,
supervision, deployment, or replacement.

## Conceptual architecture

2Ravens has two conceptual responsibilities:

```text
2Ravens
├── Munin — memory
│   ├── fact production
│   ├── synchronization
│   ├── evidence and provenance
│   └── graph storage and retrieval
└── Hugin — thought
    ├── task-oriented projections
    ├── context selection and compression
    ├── MCP
    ├── visualization
    └── review and debugging workflows
```

These names help reason about responsibilities. They are not application or
process boundaries until implementation evidence makes them useful as such.

## System flow

```text
Source files ───────┐
Git revisions ──────┤
Compiler evidence ──┤
Test observations ──┼→ fact producers → semantic evidence graph
Runtime sessions ───┘                         ↓
                                     task-oriented projections
                                               ↓
                            MCP / review UI / runtime explorer
```

The product grows by adding evidence and projections, not by replacing the
foundation for each phase:

- Phase 1 builds static facts and the AI context projection.
- Phase 2 adds before-and-after change projections and a review UI.
- Phase 3 adds OTP exploration and scoped runtime evidence.

## Authority and source materialization

The graph index is derived and disposable:

```text
Source code = implementation authority
Git = revision authority
Tests = behavioral evidence
Runtime sessions = observed evidence
Graph index = regenerable projection
```

The graph should store relationships, retrieval metadata, and references to
source ranges. Exact source must be read from the relevant repository revision
when constructing context.

The graph must never silently return source from a different revision than the
relationships being presented.

## Semantic evidence model

### Nodes

The model should grow from product needs. Likely node types include:

- Application
- Source file
- Module
- Function
- Function clause
- Behaviour and callback
- Test and test scenario
- Supervisor and process
- Process message
- Runtime session and event

Phase 1 should implement only the subset required by its benchmark.

### Relationships

Likely relationships include:

- Defines
- Calls
- Implements callback
- Tested by
- Supervises
- Sends message
- Handles message
- Observed during
- Changed between revisions

Inverse relationships such as “called by” may be query projections rather than
separately stored facts.

### Evidence

The same fact may have several evidence records:

```text
Function A calls Function B
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

Combining evidence must not discard provenance.

### Stable identity

Identifiers should survive irrelevant line movement where practical. Function
identity can begin with module, name, and arity. Clause identity additionally
needs file, clause position, and a structural fingerprint of its patterns and
guards.

Line numbers alone are not stable enough for clause or test-scenario identity.

## Freshness and uncertainty

Every query or view must be able to report:

- Repository revision
- Working-tree state
- Files indexed successfully
- Files with stale or incomplete fragments
- Compiler evidence that is current or stale
- Unresolved dynamic relationships
- Inferences that are not confirmed by observation

Uncertainty is part of the domain model, not presentation metadata added later.

## Repository perspectives

The system eventually needs three related perspectives:

- **Base graph:** the selected Git base or commit
- **Working graph:** current files, including uncommitted edits
- **Change projection:** added, removed, or modified facts between the two

Phase 1 needs enough revision awareness to materialize correct source. Phase 2
turns the difference into a first-class review model.

## Fact production

### Source parsing

The initial implementation should use Elixir-native parsing for valid source.
It should extract only the structures required by Phase 1.

Compilation must enrich rather than gate source indexing. An agent may need
context while a working tree does not compile.

For invalid intermediate files, the first implementation may preserve the last
valid file fragment and report it as stale. A tolerant parser should be adopted
only if evaluation shows that this behavior is insufficient.

### Compiler reconciliation

Compiler tracers, `mix xref`, or other compiler metadata may confirm and enrich:

- Resolved module relationships
- Imports and aliases
- Macro-generated relationships
- Behaviours and protocols
- Compile-time dependencies

Compiler evidence must retain its own revision and must not silently override
newer source-derived facts.

### Test and runtime evidence

Test capture and runtime capture are later fact producers. They should append
observed evidence to the same model rather than inventing a disconnected trace
schema.

Observed values require redaction, structural limits, and explicit retention
rules.

## Index updates

The first Phase 1 slice may use explicit repository indexing. This keeps the
product experiment focused on context quality.

When continuous indexing becomes necessary, updates should use per-file graph
fragments:

```text
File event
→ debounce and content hash
→ parse file fragment
→ atomically replace prior fragment
→ mark compiler evidence stale
→ refresh affected projections
```

An invalid update must not destroy the last known valid fragment without making
that loss visible.

## Query and projection architecture

Raw graph traversal is not a user interface. Hugin should expose opinionated
projections such as:

- Change context
- Symbol context
- Affected flow
- Test evidence
- Process context
- Runtime session

Projection construction has three steps:

```text
Candidate retrieval
→ task-aware ranking and compression
→ exact source materialization
```

Ranking may use graph distance, entry-point importance, boundary crossings,
side effects, test evidence, documentation, runtime evidence, and token cost.
The first ranking implementation should be deterministic and explainable before
it becomes sophisticated.

## Interfaces by phase

### Phase 1

- A testable Elixir context API
- One primary MCP tool
- Structured Markdown and JSON
- A basic graph explaining the selected context

### Phase 2

- A local change-review UI
- Before-and-after graph projections
- Progressive evidence and source drill-down
- Copyable review context

### Phase 3

- Static OTP exploration
- Explicit, bounded runtime attachment
- Timeline and replay of captured evidence
- Process, message, state, error, and supervision views
- Copyable debugging context

Human and AI interfaces must use the same projections and evidence semantics.

## Runtime architecture constraints

Runtime attachment is development/test-oriented and opt-in by default. A
capture session must bound its modules, processes, duration, event count,
queues, and value policy.

The runtime path must support:

- Backpressure, sampling, or explicit dropping
- Structural value limits and redaction
- Authentication and local binding by default
- Disclosure of tracing mode and overhead
- Isolation of operations that could block schedulers
- Clear separation of confirmed events and inferred causality

A native component or separate collector should be selected only after the
capture workflow defines its performance and isolation requirements.

## Initial implementation direction

Phase 1 should begin with:

- One Mix application
- Small modules separated by explicit data contracts
- Elixir-native source parsing
- Compiler evidence where it improves the benchmark
- In-memory or ETS-backed graph structures
- Explicit indexing
- One MCP adapter over a pure context API
- Deterministic tests built from small fixture repositories

Persistence, continuous watching, tolerant parsing, and alternative stores can
be introduced behind focused boundaries when there is a demonstrated need.

## Decisions intentionally deferred

- Umbrella application boundaries
- Persistent graph storage technology
- Embedded native storage
- Tolerant incomplete-source parser
- Production graph visualization library
- Runtime-agent transport and isolation model
- Distributed tracing
- Production observation
- Vector-assisted ranking

These are technical hypotheses, not parts of the product promise.

## Architectural principles

1. Source, Git, tests, and runtime events remain authoritative.
2. Every graph fact has inspectable provenance.
3. Provisional, confirmed, observed, and inferred facts remain distinguishable.
4. Compiler information enriches rather than gates source indexing.
5. Exact source is materialized from the relevant revision.
6. Graph projections are task-oriented and progressively disclosed.
7. Human and AI products share one evidence model.
8. Runtime capture is explicit, scoped, bounded, and safe by default.
9. Storage and transports remain replaceable.
10. Architecture grows only when a validated product workflow requires it.
