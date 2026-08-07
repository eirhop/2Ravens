# Roadmap

## Planning rule

2Ravens begins with one managed-authoring MVP, followed by three product phases
built on the same source-derived graph:

```text
MVP: greenfield semantic authoring
Phase 1: possible execution
Phase 2: changed possibilities
Phase 3: observed execution
```

Each phase must deliver a useful workflow and pass an evidence-based gate
before product development moves to the next.

## Current status

**Greenfield semantic-authoring MVP ready for implementation**

The immediate work is to prove that 2Ravens can create and safely change a
small ordinary Elixir application. It will derive a narrow graph from only the
files it manages, qualify every applied change, and reconstruct the same graph
from generated source. General brownfield indexing remains the next Phase 1
expansion.

## MVP foundation — managed semantic authoring

[Developer scope](scopes/01-greenfield-authoring-mvp.md) ·
[Semantic-editing contract](EDITING.md)

Goal:

> Let an AI create, inspect, and safely change a small greenfield Elixir system
> through 2Ravens while keeping ordinary source and Git recoverable.

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

Do not add a database, daemon, MCP write tool, UI, custom language, or general
brownfield importer before this gate passes.

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

[Developer scope: greenfield semantic authoring MVP](scopes/01-greenfield-authoring-mvp.md)

Implement the scope checkpoint by checkpoint, beginning with a disposable Mix
project and one generated module. The milestone passes when the complete
two-module creation, relationship query, one-token edit, qualification, apply,
and read-back workflow succeeds through ordinary Elixir APIs and `mix ravens`.

Use the [copy-paste implementation prompt](scopes/01-implementation-prompt.md)
to hand the bounded scope to a developer.
