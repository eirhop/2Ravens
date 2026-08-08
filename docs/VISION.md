# Vision

## The problem

AI is making software faster to produce, but not easier to understand.

An agent working in an unfamiliar repository may need many searches, file
reads, caller lookups, test inspections, and runtime checks before it can make
one safe change. A human reviewing that work repeats much of the same
reconstruction.

The difficult questions are behavioral:

- How can execution reach this code?
- What can this code call or affect?
- Which clauses and guards control the paths?
- How do values move between functions?
- Which OTP processes and messages participate?
- Which tests exercise the possible paths?
- What changed, and what remains uncertain?

Files, diffs, logs, and text search expose pieces of the answer. They do not
provide the execution map.

## The vision

2Ravens is a local understanding layer for Elixir and OTP systems.

It parses a repository into a graph of statically knowable structure and
behavior: applications, modules, functions, clauses, patterns, guards, calls,
argument flow, tests, processes, messages, state, and effects.

An agent or human can then request the smallest graph slice that answers the
current question instead of reconstructing that slice manually.

The graph is not a claim that every Elixir relationship is statically
knowable. Dynamic calls, generated code, protocol dispatch, and process
destinations must remain visible as possible or unresolved relationships.

The first proof was deliberately smaller and write-first. 2Ravens now creates
and edits a constrained greenfield Elixir project, derives relationships from
the source it produced, and verifies that its semantic model survives
formatting, compilation, tests, and source read-back.

The next proof adds local authoring-time semantic memory. It tests whether
preserving intent, stable identity, and typed evidence reduces cumulative AI
context across later work compared with files alone and retrospective indexing.
General brownfield understanding follows only after this value is measured.

## One foundation across three phases

The product follows one coherent progression:

```text
MVP 1:   Can 2Ravens create and safely change ordinary Elixir?
         Managed semantic authoring — implemented

MVP 2:   Does authoring-time memory reduce cumulative context?
         Persistent semantic memory — active

Phase 1: What could happen?
         Possible execution graph

Phase 2: What possibilities changed?
         Before-and-after execution graphs

Phase 3: What actually happened?
         Observed trace over the possible graph
```

### Phase 1 — AI context

Build the repository graph once. Let an AI explore it through one flexible,
deterministic context query that can begin at a repository, application,
module, function, change, test, keyword result, or several focus nodes.

The target outcome is to replace many manual exploration operations with one to
three graph queries without reducing correctness.

The MVP before this phase indexes only files created and managed by 2Ravens.
Phase 1 broadens that proven read-back boundary to arbitrary existing
repositories.

### Phase 2 — Behavior-first review

Compare the possible execution graph before and after a change. A reviewer
should see changed paths, clauses, messages, effects, tests, and uncertainty
before reading every implementation detail.

### Phase 3 — Runtime understanding

Capture one bounded local execution and overlay the observed path on the
possible graph. A developer should be able to follow functions, processes,
messages, state transitions, errors, and supervisor responses.

Each phase must be useful on its own and must prove the foundation required by
the next.

## Core principles

### Local and private by default

Every core capability must run on the developer's machine after installation.
2Ravens requires no account, API key, hosted service, cloud model, embedding
model, or external database. Network integrations may be optional adapters but
must never be required for the complete local workflow.

### Preserve intent and derive evidence

2Ravens should derive relationships from source, compiler evidence, tests,
Git, and runtime observations. Codebases should not need 2Ravens-specific
annotations or duplicated declarations that can become stale.

When an author already knows why a function or test exists, 2Ravens may retain
that concise intent as requested knowledge. It must remain distinguishable from
derived relationships and observed evidence.

Ordinary `@moduledoc`, `@doc`, typespecs, behaviours, tests, and architecture
documents enrich graph nodes because they are already useful parts of an
Elixir system.

### The agent understands the task

The coding agent already interprets the user's request. It supplies explicit
focus nodes and traversal needs. 2Ravens supplies deterministic repository
facts; it does not reinterpret free-text tasks with another model.

### Authority remains outside 2Ravens

Source and Git define the implementation and revision. Tests and runtime events
provide behavioral evidence. A local embedded store may retain operational
semantic memory, but it is not the only recoverable copy of the program.

### Evidence and uncertainty are visible

Source-derived, compiler-confirmed, test-observed, runtime-observed, possible,
and unresolved relationships must not be presented as equivalent. Unknown
behavior remains unknown.

### Query behavior, not files

Raw graph neighborhoods quickly become overwhelming. Queries should follow
meaningful paths from entry points to focus nodes, from focus nodes to effects,
from senders to message handlers, and from tests to exercised code.

### Reuse understanding when changing code

An agent creates substantial implementations as ordinary Elixir. Once 2Ravens
has resolved a precise program element, the agent can reuse that revision-bound
identity for a compact known change instead of repeating file paths and textual
patch context. Every accepted candidate materializes inspectable source and is
re-derived from that source before it becomes trusted graph evidence.

### Use progressive disclosure

An agent or human may begin with a shallow module view, continue with a function
execution envelope, and finally inspect one clause or uncertain path. Source is
materialized only for selected nodes and never duplicated unnecessarily.

### Measure real improvement

The product succeeds only when agents or humans complete real work faster or
more accurately. Graph size and technical sophistication are not product
outcomes.

## Hugin and Munin

The project uses two conceptual names:

- **Munin — memory:** parsing, compiler reconciliation, synchronization,
  provenance, and repository-graph storage.
- **Hugin — thought:** graph slicing, execution envelopes, MCP, visualization,
  review, and debugging workflows.

They describe responsibilities. They should become separate applications only
if implementation experience demonstrates a useful boundary.

## Long-term destination

An AI should be able to request the relevant execution slice instead of
spending many steps reconstructing callers, dependencies, tests, and effects.

When that slice identifies a safe edit target, the AI should be able to propose
the smallest clear change and receive its source and behavior impact without
manually describing graph relationships that 2Ravens can derive. Intent captured
during earlier work should be reusable without repeatedly rereading or
reconstructing it.

A reviewer should be able to see how the possible behavior changed before
reading the complete diff.

A developer should be able to see the actual runtime path highlighted inside
the set of paths that could have happened.

2Ravens succeeds when understanding an Elixir system becomes closer to
navigating an execution map than assembling a story from disconnected files
and logs.
