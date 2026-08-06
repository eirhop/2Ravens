# Product plan

## Product thesis

2Ravens turns a local Elixir repository into a queryable execution map.

Today, a capable coding agent often builds that map manually:

```text
Task
→ find an anchor
→ inspect its contract
→ follow callers to entry points
→ follow calls to effects
→ trace values and branch conditions
→ inspect tests
→ resolve uncertainty at runtime
```

2Ravens should make the repository-understanding portion available in one to
three deterministic graph queries.

```text
Source + compiler + tests + Git + local runtime observations
                            ↓
                   Repository evidence graph
                            ↓
                   Explicit graph-slice query
             ┌──────────────┼──────────────┐
             ↓              ↓              ↓
         AI context      Change review   Runtime explorer
```

## The product boundary

The agent understands the user's task and decides what it needs to explore.
2Ravens understands repository relationships and returns the requested slice.

The initial API therefore does not accept open-ended task prose. It accepts
structured focus, traversal, inclusion, input-constraint, and output-limit
parameters. Keyword search is local and lexical; it resolves candidate anchors
rather than pretending to understand intent.

See the complete [context-query contract](QUERY.md).

## Local-first guarantee

After installation, every core workflow must run with network access disabled:

- Index a repository
- Resolve exact symbols and local keyword matches
- Query single-focus and multi-focus graph slices
- Produce an input-sensitive execution envelope
- Display a local review
- Capture a local development or test execution

Core functionality must not require:

- Accounts or API keys
- Cloud services
- Embedding models
- Learned rerankers
- Hosted vector databases
- External database servers
- Mandatory Docker infrastructure
- Hidden network calls or telemetry

Optional integrations may connect to remote products, but they cannot replace
or weaken the complete local workflow.

## Target users

### AI coding agents

They need precise, bounded graph slices with exact source, stable identities,
visible traversal limits, and unresolved relationships.

### Human reviewers

They need to compare the possible execution paths before and after a change,
including branches, messages, effects, tests, and uncertainty.

### Developers learning or debugging a system

They need to navigate the possible graph and see an observed execution
highlighted within it.

The users are served in that order because each later product depends on the
same graph being trustworthy.

## The three phases

| Phase | Product question | Primary proof |
| --- | --- | --- |
| [1. AI context](phases/01-ai-context.md) | What could happen from these focus nodes? | Agents replace substantial manual exploration with one to three graph queries without losing correctness. |
| [2. Behavior-first review](phases/02-behavior-review.md) | What possible behavior changed? | Reviewers understand behavioral impact faster and identify important risks or missing evidence. |
| [3. Runtime understanding](phases/03-runtime-understanding.md) | What actually happened? | Developers explain a real execution by following its observed path through the possible graph. |

Each phase has an explicit gate. Later phases may be researched, but product
development should not move through a gate until the previous promise has been
validated.

## Shared product model

### Repository graph

The graph represents the complete set of statically knowable relationships in
the repository. It includes structural, call, control-flow, dataflow, test, OTP,
and documentation information. Dynamic behavior is represented as candidate or
unresolved relationships rather than omitted or guessed.

### Execution envelope

The repository graph is the static supergraph. An execution envelope is the
subset that could execute from one or more focus nodes under optional input
constraints.

It is similar to a branching stack trace:

```text
Function
├── clause and guard A → call path → effect
└── clause and guard B → alternative path → return shape
```

2Ravens does not need to execute arbitrary application code or calculate
concrete results. It follows patterns, guards, branches, calls, argument
mappings, messages, and abstract values as far as static evidence permits.

### Change projection

Phase 2 compares base and working execution envelopes. It shows added, removed,
or changed nodes, edges, paths, conditions, effects, and evidence.

### Observed trace

Phase 3 records one bounded local execution and highlights the actual path
inside the execution envelope. Possible but unobserved paths remain visible.

### Facts and evidence

A relationship may have several evidence records:

```text
CALLS relationship
├── source parser: probable
├── compiler: confirmed
├── test capture: observed
└── runtime capture: observed
```

Evidence may strengthen a relationship, but stronger evidence must not erase
its provenance.

## Product-wide non-goals

2Ravens is not intended to become:

- A code editor
- An autonomous coding agent
- An agent harness
- A replacement for Git or GitHub
- A replacement for ExUnit
- A canonical source-code store
- A cloud indexing service
- A general production APM or distributed tracing platform
- A system that requires codebases to add 2Ravens-specific annotations
- A semantic search product based on embeddings or learned reranking

## Planning principles

### Build the graph once and slice it many ways

Index the repository independently of a user task. Queries choose focus,
directions, relationships, stopping points, constraints, and limits.

### Derive facts from the system

Callers, effects, process relationships, tests, and ownership should be derived
from code and evidence. When they cannot be derived, show the uncertainty
instead of adding a second declaration that can become stale.

### Preserve paths, not only neighborhoods

The useful result is often entry point → focus → effect, test → focus, or
sender → message → handler. A raw fixed-hop neighborhood is only an exploration
tool.

### Deduplicate multi-focus context

A query with several focus nodes returns one combined subgraph. Common callers,
dependencies, tests, effects, documentation, and source appear once and record
which focus nodes they explain.

### Keep technical decisions reversible

Storage engines, parser fallbacks, UI renderers, and runtime transports should
be selected from measured requirements. They are not product commitments.

### Validate against real work

Benchmarks should compare the agent's existing exploration with 2Ravens on
representative Elixir tasks. Synthetic fixtures prove deterministic graph
semantics; real repositories prove product value.

## Decisions intentionally deferred

The product plan does not yet select:

- A persistent embedded graph store
- Tree-sitter or another incomplete-source parser
- An umbrella application structure
- A production UI graph renderer
- A runtime-agent transport
- Production runtime observation

These choices should be made only when a validated workflow creates a concrete
requirement, while preserving the local-first guarantee.
