# Roadmap

## Planning rule

2Ravens has three product phases. Each phase must deliver a useful workflow and
pass an evidence-based gate before product development moves to the next.

Research may look ahead when it reduces a known risk, but it must not turn into
building later-phase infrastructure before the current product promise is
validated.

## Current status

**Product definition and Phase 1 preparation**

The repository currently contains the product vision and plans. The immediate
work is to finish the Phase 1 contract and benchmark before selecting broad
architecture or building a product shell.

## Preparation — product contract and benchmark

This is preparation for Phase 1, not a separate product phase.

Deliverables:

- Accepted three-phase product plan
- Example `get_change_context` inputs and complete expected outputs
- A benchmark set of representative Elixir changes and tasks
- Human-reviewed reference context for each benchmark task
- A reproducible baseline of agent work without 2Ravens
- Focused technical spikes for source ranges, function calls, tests, and
  compiler evidence

Exit condition:

- The first product workflow and its evaluation can be implemented without
  inventing the user contract during development.

## Phase 1 — AI context

[Full phase plan](phases/01-ai-context.md)

Goal:

> Given one changed Elixir function and a task, return the smallest trustworthy
> context needed to make a correct change.

Milestones:

1. Benchmark and context contract
2. Static extraction of the facts required by the benchmark
3. Task-aware change-context projection
4. One MCP tool and one basic visual explanation
5. Evaluation on real agent tasks

Gate:

- Agents complete representative work at least as correctly as the baseline.
- Repository exploration and context cost are materially reduced.
- Provenance, freshness, omissions, and uncertainty are inspectable.

## Phase 2 — Behavior-first review

[Full phase plan](phases/02-behavior-review.md)

Goal:

> Explain what a change does and what it can affect before the reviewer reads
> every line of the diff.

Milestones:

1. Review contract and evidence language
2. Before-and-after graph projection
3. Minimal local change-review UI
4. Comparative review evaluation
5. Commit, branch, and optional pull-request integration

Gate:

- Reviewers answer important impact questions faster and with equal or better
  accuracy than the baseline workflow.
- The UI does not present inferred impact as confirmed behavior.
- Tests, uncertainty, source, and the original diff remain inspectable.

## Phase 3 — Runtime understanding

[Full phase plan](phases/03-runtime-understanding.md)

Goal:

> Make an unfamiliar Elixir system explorable and make one concrete execution
> or failure explainable.

Milestones:

1. Static OTP system explorer
2. Bounded ExUnit capture
3. Attached local development capture
4. Timeline, replay, and grounded explanation
5. Comparative exploration and debugging evaluation

Gate:

- An unfamiliar developer can identify the processes and state owners involved
  in a behavior.
- A bounded interaction can be captured and explained through functions,
  messages, state transitions, errors, and supervisor responses.
- Runtime observations and inferred causality remain clearly distinguished.

## Later opportunities

These ideas are outside the initial three-phase commitment and require separate
validation:

- Historical graph comparisons
- Architecture boundary rules
- Detection of undesirable dependencies
- Suggested missing tests
- An isolated manual function workbench
- Test generation from captured sessions
- Static-versus-runtime drift
- Distributed BEAM and cross-node message flow
- Production-safe sampled observation
- Semantic or vector-assisted ranking
- Architecture documentation generation
- Hot-code-upgrade visualization

## Immediate next milestone

Before implementing the index:

1. Select the initial benchmark repository and representative tasks.
2. Write the expected context package for one changed Elixir function by hand.
3. Define the evidence and freshness fields in that package.
4. Record the baseline agent workflow for the same task.
5. Run only the technical spikes needed to reproduce that package from source
   and compiler evidence.

The first implementation milestone is complete when the hand-written package
can be produced automatically through one MCP tool and inspected as one basic
graph.
