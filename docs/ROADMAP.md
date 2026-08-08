# Roadmap

## Planning rule

2Ravens begins with bounded MVP experiments, followed by three product
phases built on the same semantic evidence graph:

```text
MVP 1: greenfield semantic authoring — implemented
MVP 2: persistent semantic memory — implemented; gate failed
MVP 3: entity-based batch authoring — implemented; replication gate open
Phase 1: possible execution
Phase 2: changed possibilities
Phase 3: observed execution
```

Each phase must deliver a useful workflow and pass an evidence-based gate
before product development moves to the next.

## Current status

**Agent-native entity authoring under replication**

Scope 01 proved safe source materialization. Scope 02 implemented local
semantic memory, but its frozen lifecycle remained larger than source-indexed
context. A batch API now submits ordered entity operations once, retains
invalid requests and compiler-invalid drafts for repair, and qualifies one
atomic candidate. Scope 04 adds flat MCP tools, canonical discovery, tolerant
bounded selectors, same-call proof, and exact test editing. Its first final
paired lifecycle beat files on tokens, calls, and wall time. The next gate is
independent repetition, not broader infrastructure.

## MVP foundation 1 — managed semantic authoring

[Developer scope](scopes/01-greenfield-authoring-mvp.md) ·
[Semantic-editing contract](EDITING.md)

Goal:

> Let an AI create, inspect, and safely change a small greenfield Elixir system
> through 2Ravens while keeping ordinary source and Git recoverable.

Status: implemented in `b85d23d`.

Milestones:

1. Initialize small management metadata in an existing new Mix project.
2. Create modules and functions from normal Elixir input.
3. Read managed files back into a deterministic in-memory graph.
4. Derive function, clause, call, guard, and test relationships.
5. Return compact context and a stateless revision-bound edit handle.
6. Dry-run and explicitly apply one comparison-operator edit.
7. Qualify candidates through formatting, compilation, tests, and graph/source
   round-trip checks.
8. Compare the same creation and edit workflow with ordinary file operations.

Gate:

- Generated files remain ordinary formatted Elixir.
- A new CLI process reconstructs the accepted graph from managed source.
- Relationships are derived rather than asserted by the caller.
- Stale targets, unsafe paths, and unsupported structures fail explicitly.
- Applied changes affect only intended managed paths.
- The end-to-end workflow is no less correct than direct file editing.

The technical gate passed. The mechanics comparison did not show efficiency,
so more authoring verbs remain deferred. It justified only the bounded semantic
memory experiment below, not broader infrastructure.

## MVP foundation 2 — persistent semantic memory

[Hypothesis and decision gate](SEMANTIC_MEMORY.md) ·
[Developer scope](scopes/02-semantic-memory-mvp.md)

Goal:

> Preserve authoring-time knowledge that source indexing loses and determine
> whether it reduces cumulative context across later AI work.

Milestones:

1. Add a local SQLite semantic store behind a small adapter.
2. Persist stable entities, concise intent, typed relations, evidence, source
   projections, and accepted operations.
3. Keep requested, source-derived, compiler-confirmed, test-observed, and
   reconstructed origins separate.
4. Reuse current memory across independent CLI processes.
5. Detect source/store drift and reconcile only derived facts.
6. Return compact successful receipts and focused context by default.
7. Compare files-only, source-indexed, and semantic-memory lifecycle conditions.
8. Report cumulative context break-even or failure honestly.

Gate:

- Semantic memory preserves useful facts unavailable to indexing.
- It reaches cumulative context break-even within the frozen task sequence.
- Later tasks use less cumulative model input after break-even.
- Correctness is preserved or improved.
- Freshness, provenance, uncertainty, and missing intent remain explicit.

The cumulative-context gate failed against source indexing. Do not expand the
store into Ecto, a graph database, portable synchronization, UI, or brownfield
infrastructure from that result. Scope 03 below is a separate bounded response
to measured authoring round trips, not an expansion justified by Scope 02.

## MVP foundation 3 — entity-based batch authoring

[API contract](ENTITY_AUTHORING.md) ·
[Developer scope](scopes/03-entity-authoring-mvp.md)

Goal:

> Let an agent create new Elixir freely, then edit existing modules only through
> exact module, function, clause, and module-form entities in one repairable
> atomic request.

Milestones:

1. Accept one ordered JSON-shaped operation list.
2. Split a free-form bundle only when every submitted module is new.
3. Add and edit existing functions and ordered clauses as module children.
4. Cache invalid large requests and repair one entity by draft ID.
5. Project conventional source, qualify once, and commit source/store together.
6. Re-run the live-agent probe with fewer calls and equal correctness.

The API deliberately excludes whole-existing-module merge, custom macros,
caller-supplied relations, and speculative metadata.

Status: implemented through Scope 04. The final
[three-job lifecycle](../benchmarks/entity_authoring/lifecycle_luna_2026-08-08.md)
completed correctly and used 48.4% fewer total tokens, 45.5% fewer wrappers,
and 38.4% less wall time than files. Treat that as a successful frozen probe,
not a general efficiency theorem. The remaining gate is repetition across
fresh paired lifecycles before advancing the product phase.

## Preparation — contract and benchmark

This is preparation for Phase 1, not a separate product phase.

Deliverables:

- Accepted three-phase product plan
- Accepted [context-query contract](QUERY.md)
- Representative single-focus and multi-focus scenarios
- Hand-written expected graph slices for those scenarios
- A reproducible baseline of agent exploration without 2Ravens
- Focused spikes for functions, clauses, argument flow, macros, tests, and one
  GenServer message path
- An offline acceptance requirement for every core workflow

Exit condition:

- The first graph and query can be implemented without inventing the product
  contract during development.

## Phase 1 — AI context

[Full phase plan](phases/01-ai-context.md)

Goal:

> Replace substantial manual repository exploration with one to three local,
> deterministic graph queries.

Milestones:

1. Query contract and benchmark
2. Complete function and clause supergraph for the benchmark repository
3. Call-site argument mapping and bounded execution envelope
4. Macro, test, and static OTP relationships
5. Flexible single-focus and multi-focus graph slicing
6. `mix ravens`, one local MCP `context` tool, and a basic graph view
7. Comparative agent evaluation

Gate:

- Agents complete representative work at least as correctly as the baseline.
- Manual exploration operations and context duplication are materially reduced.
- Possible paths, unresolved relationships, freshness, and traversal limits are
  inspectable.
- The complete workflow runs offline without credentials.

## Phase 2 — Behavior-first review

[Full phase plan](phases/02-behavior-review.md)

Goal:

> Compare the possible execution graph before and after a change so a reviewer
> can see what behavior may have changed.

Milestones:

1. Review contract and evidence language
2. Base and working repository graphs
3. Before-and-after execution-envelope comparison
4. Minimal local change-review UI
5. Comparative review evaluation
6. Optional commit, branch, and pull-request integrations

Gate:

- Reviewers answer important impact questions faster and with equal or better
  accuracy than the baseline workflow.
- Shared context for multi-function changes is merged rather than repeated.
- Possible, confirmed, observed, and unresolved behavior remain distinct.
- Tests, source, uncertainty, and the original diff remain inspectable.

## Phase 3 — Runtime understanding

[Full phase plan](phases/03-runtime-understanding.md)

Goal:

> Overlay one bounded observed execution on the possible graph and explain what
> actually happened.

Milestones:

1. Static OTP system explorer
2. Bounded ExUnit capture
3. Attached local development capture
4. Observed-path overlay on the execution envelope
5. Timeline, replay, and grounded explanation
6. Comparative exploration and debugging evaluation

Gate:

- An unfamiliar developer can identify the processes and state owners involved
  in a behavior.
- A bounded local interaction can be followed through functions, messages,
  state transitions, errors, and supervisor responses.
- The actual path is visible within the possible paths.
- Runtime observations and inferred causality remain clearly distinguished.

## Later opportunities

These ideas are outside the initial three-phase commitment and require separate
validation while preserving local operation:

- Historical graph comparisons
- Architecture boundary rules
- Detection of undesirable dependencies
- Suggested missing tests
- An isolated manual function workbench
- Test generation from captured sessions
- Static-versus-runtime drift
- Distributed BEAM and cross-node message flow
- Production-safe sampled observation
- Architecture documentation generation
- Hot-code-upgrade visualization

## Immediate next milestone

[Developer scope: entity-based batch authoring MVP](scopes/03-entity-authoring-mvp.md)

Implement strict request validation and split two new modules from one source
bundle first. Then add exact function/clause edits, versioned draft repair,
single qualification, atomic projection, and the live-agent probe.
