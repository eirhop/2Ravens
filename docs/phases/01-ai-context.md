# Phase 1 — AI context

## Status

Planned. This begins after the persistent semantic-memory MVP gate.

Scope 01 proves safe creation, narrow read-back indexing, graph identities,
qualification, and one semantic edit for 2Ravens-managed files. Scope 02 tests
persistent intent, evidence, compact context, and cumulative context value.
Phase 1 expands the validated boundary to arbitrary existing repositories; it
does not need to reinvent the authoring or semantic-memory loop.

## Product promise

Replace substantial manual repository exploration with one to three precise,
deterministic graph queries.

An AI agent should be able to begin broadly at a repository or module, narrowly
at a function or test, or jointly at several focus nodes. It should receive the
possible paths, dependencies, tests, effects, source, and uncertainty required
to continue its task.

## Why this is valuable

A capable coding agent typically performs a repeated sequence:

1. Find an initial symbol.
2. Read its contract and clauses.
3. Search for callers and entry points.
4. Follow calls to effects and boundaries.
5. Trace arguments, branches, messages, and state.
6. Find tests and analogous behavior.
7. Repeat searches when the first hypothesis is incomplete.

Phase 1 builds that repository map ahead of time and makes it directly
queryable. The agent retains responsibility for understanding the user's task
and deciding what to explore.

## Product boundary

2Ravens does not accept open-ended task prose and does not use embeddings,
learned rerankers, or cloud models to guess relevance.

The agent calls one operation with structured parameters:

```text
context(
  focus,
  traversal,
  include,
  constraints,
  limit
)
```

See [Context query](../QUERY.md) for the complete contract and usage scenarios.

## Primary workflow

1. 2Ravens indexes the complete statically knowable repository graph.
2. The agent converts its understanding of the task into focus and traversal.
3. 2Ravens resolves the focus and constructs the requested graph slice.
4. Optional input constraints prune impossible clauses and branches.
5. Exact source is materialized once for selected nodes.
6. The response discloses evidence, freshness, ambiguity, and unexpanded scope.
7. The agent may continue from a returned node ID using the same operation.

An exact function may require one query. A vague issue may require a shallow
keyword or module query followed by a focused execution-envelope query. A
dynamic or ambiguous path may require one additional expansion.

## Entry criteria

Begin general brownfield implementation only after the semantic-memory MVP
proves:

- Generated source reconstructs to the accepted graph in a new CLI process.
- Canonical identities and stale-handle detection work for the supported subset.
- Derived calls and tests remain deterministic after formatting and compilation.
- Unsafe or unsupported writes fail without modifying source.
- The graph/source round-trip and qualification boundaries are reusable.
- Persisted memory preserves useful facts unavailable to indexing.
- The lifecycle benchmark reaches cumulative context break-even without
  reducing correctness.

## First complete vertical slice

Given one Elixir function, return:

- Its module, documentation, typespec, clauses, patterns, and guards
- Explicit local and remote callees
- Call-site argument and result mappings
- Direct callers
- Paths from meaningful entry points to the function
- Paths from the function to effects or application boundaries
- Relevant tests
- Static OTP message relationships where present
- Exact source ranges and selected source
- Candidate or unresolved dynamic relationships
- Index freshness and unexpanded frontier

Optional abstract input constraints should narrow the possible clauses and
branches without executing arbitrary application code.

## Required capabilities

### Complete statically knowable graph

Parse every repository source file and index:

- Applications, files, modules, functions, macros, and clauses
- Patterns, guards, and branches
- Explicit local, remote, and imported calls
- Call sites and argument/result mappings
- Behaviours, callbacks, protocols, structs, and types
- Tests, doctests, ordinary documentation, and typespecs
- Git base and working-tree changes
- Source ranges and revision identity

The graph should terminate external dependencies at explicit boundaries until
there is evidence that dependency source must be indexed.

### Macro and compiler reconciliation

Preserve macro invocation relationships and compiler-generated relationships.
Use compiler evidence to confirm or enrich the source graph without making
successful compilation a prerequisite for indexing.

### Static OTP relationships

Resolve common GenServer calls, casts, sends, message patterns, callbacks,
supervisors, and registered process identities. Map sent values to handler
patterns when possible. Ambiguous process destinations remain visible.

### Execution envelope

Starting from one or more focus nodes, follow every path compatible with known
patterns, guards, branches, abstract inputs, and traversal limits.

Return function calls, message paths, effects, return shapes, and exceptions
when statically knowable. Unknown expressions preserve every compatible path.

### Multi-focus graph slicing

For several focus nodes:

- Find common upstream and downstream relationships.
- Find meaningful paths connecting the focus nodes.
- Merge shared nodes and path segments.
- Materialize shared source, documentation, and tests once.
- Separate shared and focus-specific context.
- Return disconnected components honestly when no meaningful connection exists.

### Local keyword discovery

Support deterministic lexical matching over names, identifiers, docs,
typespecs, tests, paths, and source. Return candidate anchors and ambiguity; do
not infer task intent.

### Progressive expansion

Every bounded query returns an unexpanded frontier. The agent can continue from
returned node IDs through the same `context` operation. No separate search,
expand, test, or architecture tools are required initially.

## Interfaces

The domain API is transport-independent:

```text
Mix task:   mix ravens
MCP server: two_ravens
MCP tool:   context
```

The Mix task supports development, diagnostics, and benchmarks. The thin local
STDIO MCP adapter is the preferred agent surface and remains bound to one
project root.

## Delivery milestones

### 1. Query contract and benchmark

- Select representative repository-understanding scenarios.
- Record the agent's existing searches, file reads, and commands.
- Hand-write the expected graph slice for each scenario.
- Define expected nodes, paths, exclusions, uncertainty, and frontier.

### 2. Function and clause supergraph

- Parse every function and clause in a small real repository.
- Resolve explicit local and remote calls.
- Retain stable identities, exact call sites, and source ranges.
- Query callers and callees in both directions.

### 3. Control and dataflow

- Record clause patterns, guards, and branch conditions.
- Map caller expressions to callee arguments.
- Map call results into bindings and pattern matches.
- Construct one bounded input-sensitive execution envelope.

### 4. Macros, tests, and OTP

- Connect macro invocations to compiler-expanded relationships.
- Connect tests statically to the code they reference.
- Connect one GenServer message send to its handler clause.
- Represent unresolved dynamic relationships explicitly.

### 5. Flexible context query

- Support repository, module, function, test, change, keyword, and node-ID
  focus.
- Support traversal direction, relationship types, stopping points, and limits.
- Support multiple focus nodes with combined deduplicated output.
- Materialize exact source and return frontier information.

### 6. Mix and MCP adapters

- Expose the contract through `mix ravens`.
- Return stable JSON and structured Markdown.
- Expose the same contract through one local MCP `context` tool.
- Render the selected graph as a basic diagnostic visualization.

### 7. Product evaluation

- Run representative coding tasks with and without 2Ravens.
- Compare correctness, exploration operations, context cost, and omissions.
- Improve graph extraction or query semantics only where evidence identifies a
  problem.

## Initial implementation direction

- One Mix application
- Elixir-native parsing for valid source
- Compiler reconciliation for confirmed and generated relationships
- In-memory or ETS-backed graph structures before persistent storage
- Explicit indexing before continuous file watching
- Deterministic path and set operations rather than learned ranking
- No codebase-specific annotations
- No network access, credentials, models, or external database
- Small fixture repositories plus a substantial real benchmark repository

For invalid files, retain the last valid fragment with explicit stale status
until a benchmark demonstrates the need for tolerant parsing.

## Validation scenarios

The initial benchmark should include:

- Orient in an unfamiliar repository.
- Inspect a module one hop in both directions.
- Understand the possible execution from a known function.
- Narrow an execution envelope with input constraints.
- Resolve a vague issue through local keyword discovery and a second query.
- Find callers and tests before a public API refactor.
- Combine several changed functions without duplicating shared context.
- Follow a GenServer message to its handler.
- Follow a function to persistence or another side-effect boundary.
- Inspect a macro-generated relationship and its uncertainty.

Measure:

- Task correctness
- Important-node and important-path recall
- Irrelevant nodes and source
- Repository exploration operations
- Total context size
- Time to the first correct edit
- Missed dependencies and incorrect assumptions
- Follow-up graph queries

Numerical targets should be set after recording a reproducible baseline. The
tool must improve efficiency without degrading correctness.

## Risks

- Macros and dynamic dispatch can make static relationships incomplete.
- Raw fixed-hop neighborhoods can explode around common helpers.
- Abstract execution can suffer path explosion or imprecise unknown values.
- Stale graph facts can create convincing but incorrect source context.
- Multi-focus queries can over-prioritize generic shared utilities.
- Aggressive output limits can hide required context.

The response must disclose unresolved edges, analysis limits, disconnected
components, and the unexpanded frontier.

## Non-goals

Phase 1 does not include:

- Free-text task interpretation
- Embeddings, vector search, or learned reranking
- 2Ravens-specific code annotations
- A production review UI
- Runtime tracing or state capture
- Manual function execution
- Continuous production observation
- A general-purpose graph query language
- A commitment to a persistent graph database

## Exit criteria

Phase 1 is complete when:

- The statically knowable repository graph supports the agreed benchmark.
- One `context` operation supports broad-to-narrow progressive exploration.
- Single-focus and multi-focus results preserve paths and deduplicate shared
  context.
- Optional input constraints narrow a possible execution envelope.
- Relationships have inspectable provenance, confidence, revision, and
  freshness.
- Important omissions, unresolved edges, and traversal limits are visible.
- Agents complete representative tasks at least as correctly as the baseline
  with materially less manual exploration.
- The complete workflow works locally without network access or credentials.

Passing this gate demonstrates that the graph can support the human review
product.
