# Roadmap

## Planning rule

2Ravens has three product phases built on one graph:

```text
Phase 1: possible execution
Phase 2: changed possibilities
Phase 3: observed execution
```

Each phase must deliver a useful workflow and pass an evidence-based gate
before product development moves to the next.

## Current status

**Product definition and Phase 1 technical validation**

The immediate work is to prove that a real Elixir repository can become a
useful local function, dataflow, and OTP graph before building a product shell
or selecting broad infrastructure.

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

Build a technical spike that proves one complete execution slice:

1. Select a small real Elixir repository and one representative function.
2. Parse every function and clause in the repository.
3. Resolve explicit local and remote calls.
4. Record call-site argument mappings and branch conditions.
5. Connect relevant tests.
6. Connect one GenServer message send to its handler clause.
7. Query upstream paths to meaningful entry points.
8. Query downstream paths to effects or application boundaries.
9. Return the minimal subgraph with exact source, uncertainty, and frontier.
10. Repeat with two focus functions and deduplicate their shared context.

The milestone passes when `mix ravens` can reproduce the hand-written expected
slice locally and deterministically. MCP is added after this core contract is
stable.
