# Phase 1 — AI context

## Status

Planned. This is the active product phase.

## Product promise

Given a repository change and a task, return the smallest trustworthy context
an AI agent needs to make a correct change.

The first complete workflow is deliberately narrow:

> Given one changed Elixir function, return its clauses, important callers,
> important callees, relevant tests, application boundaries, exact source
> ranges, and any uncertainty.

## Why this is valuable

AI agents currently reconstruct repository context through repeated searches,
file reads, and guesses about relationships. This consumes tokens and time, and
it can omit dependencies that are not obvious from text search.

Phase 1 should reduce that exploration while making the basis for the returned
context inspectable. It also proves whether the evidence graph is accurate and
useful enough to support the later human products.

## Target user

The initial user is an AI coding agent working in a local Elixir repository.
The human supervising the agent is a secondary user who needs to inspect why
particular context was selected.

## Primary workflow

1. 2Ravens indexes the relevant repository revision and working tree.
2. The agent supplies a changed function or diff, a task description, and a
   token budget.
3. 2Ravens retrieves and ranks relevant graph facts.
4. Exact source is materialized from the current files.
5. The agent receives structured context with freshness and uncertainty.
6. The agent can request a focused expansion when the first package is
   insufficient.

The primary interface is:

```text
get_change_context(
  target,
  task,
  token_budget
)
```

The first version should prefer one useful tool over a broad family of shallow
tools. Additional symbol, flow, test, or architecture queries should be added
only when evaluation shows that focused follow-up is needed.

## Context contract

A response should contain:

- A concise summary of the selected context
- Repository revision and index freshness
- Changed modules, functions, and clauses
- Important upstream callers
- Important downstream calls and side effects
- Relevant behaviours, callbacks, and application boundaries
- Relevant tests and documented examples
- Exact source locations and selected source
- Provenance and confidence for relationships
- Unresolved dynamic relationships and other uncertainty
- Reasons that the most important items were selected

The response may omit low-value graph nodes, but it must not hide known gaps in
the evidence.

## Required capabilities

### Repository facts

The initial graph should model only facts needed by the first workflow:

- Applications and source files
- Modules
- Functions and function clauses
- Patterns and guards where they affect clause identity
- Explicit local and remote calls
- Behaviours and callbacks
- Tests and doctests
- Documentation and typespec references
- Source ranges
- Git base and working-tree changes

Macros, generated code, imports, protocols, configuration, process messages,
and supervision relationships should be added when they materially improve the
benchmark rather than merely expanding the schema.

### Evidence and freshness

The first implementation must distinguish:

- Source-derived probable relationships
- Compiler-confirmed relationships
- Unresolved or inferred relationships

If later test execution adds observed relationships, they must remain distinct
from static references to test code.

Each response must disclose which files were indexed, which compiler evidence
is current, and whether changed files are incomplete or stale.

### Context selection

Candidate facts should be ranked using evidence such as:

- Direct relevance to the changed symbol and task
- Graph distance
- Public entry-point importance
- Application or process boundary crossings
- Side effects
- Test evidence
- Documentation
- Token cost

The ranking does not need to be sophisticated initially. It needs to be
deterministic, explainable, and measurable.

### Inspectable graph

The phase includes one basic visual graph for inspecting the context package.
Its purpose is to explain and debug selection, not to deliver the full review
experience planned for Phase 2.

## Delivery milestones

### 1. Benchmark and contract

- Select representative changes from a substantial Elixir repository.
- Record the functions, tests, boundaries, and source required for each task.
- Capture baseline agent behavior without 2Ravens.
- Define example MCP responses before implementing the index.

### 2. Static extraction

- Parse one valid Elixir repository.
- Produce stable nodes, relationships, and source ranges.
- Combine source-derived and compiler-derived evidence without losing
  provenance.
- Represent a changed function and its immediate context.

### 3. Context projection

- Accept one changed function and task.
- Rank callers, callees, tests, and boundaries.
- Materialize exact source within a token budget.
- Report freshness, omissions, and uncertainty.

### 4. MCP and visual explanation

- Expose `get_change_context` through MCP.
- Return structured Markdown and JSON.
- Render the selected context as a basic graph.

### 5. Product evaluation

- Run the benchmark with and without 2Ravens.
- Inspect missed dependencies and irrelevant context.
- Improve extraction and ranking only where the evidence identifies a problem.

## Initial implementation direction

The simplest credible implementation should be preferred:

- One Mix application, with conceptual module boundaries inside it
- Elixir parsing plus compiler or `mix xref` evidence
- Explicit indexing before continuous file watching
- In-memory or ETS-backed graph structures before a graph database
- A small MCP adapter over a testable context API
- A simple generated graph rather than a production UI

For temporarily invalid files, the first version may return the last valid
fragment with explicit stale status. A tolerant parser is a later decision if
real tasks demonstrate that this is insufficient.

## Validation

Use representative tasks from a substantial Elixir codebase, initially Favn.
For each task, define a human-reviewed reference set of important symbols,
tests, boundaries, and source.

Compare agents with and without 2Ravens using:

- Task correctness
- Important-context recall
- Irrelevant context and total input tokens
- Repository exploration calls
- Time to the first correct edit
- Missed dependencies
- Incorrect assumptions
- Follow-up context requests

Numerical targets should be set after measuring a reproducible baseline. The
tool must improve efficiency without degrading correctness.

## Risks

- Macros and dynamic dispatch can make a static call graph incomplete.
- A large graph can still produce poor context if ranking is weak.
- Stale working-tree facts can create convincing but incorrect answers.
- Generated behavior summaries can overstate what static evidence proves.
- Optimizing only for fewer tokens can remove context needed for correctness.

These risks are reasons to expose evidence and benchmark the complete workflow,
not reasons to broaden the initial scope.

## Non-goals

Phase 1 does not include:

- A production review UI
- A general repository explorer
- Test execution and runtime capture
- Runtime tracing or state capture
- Manual function execution
- Continuous production observation
- Semantic or vector search unless the baseline demonstrates a need
- A commitment to a particular persistent graph database

## Exit criteria

Phase 1 is complete when:

- `get_change_context` supports the complete changed-function workflow.
- Returned relationships have inspectable provenance, confidence, and
  freshness.
- Agents complete representative tasks at least as correctly as the baseline.
- Repository exploration and context cost are materially reduced.
- Important omissions and uncertain relationships are visible.
- The same projection can be rendered as a basic graph.

Passing this gate demonstrates that the semantic graph is useful enough to
support a human review product.
