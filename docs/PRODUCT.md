# Product plan

## Product thesis

2Ravens captures and derives a local semantic memory of an Elixir system so AI
and humans can query the smallest trustworthy context needed for later changes
and review.

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
three deterministic graph queries. When code is created through 2Ravens, it may
also preserve concise intent and requested relationships that source indexing
cannot reconstruct later.

The completed first MVP proved safe greenfield authoring, derived relationships,
and deterministic source round trips. Its mechanics benchmark did not show an
efficiency advantage, and model token counts were unavailable. The next MVP
tests whether persistent authoring-time semantic memory amortizes its initial
overhead across repeated later tasks.

```text
Intent + source + compiler + tests + Git + local runtime observations
                                  ↓
                       Local semantic memory
                            ↓
                   Explicit graph-slice query
             ┌──────────────┼──────────────┐
             ↓              ↓              ↓
         AI context      Change review   Runtime explorer
```

## The product boundary

The agent understands the user's task and decides what it needs to explore.
2Ravens understands repository relationships and returns the requested slice.

The context API therefore does not accept open-ended task prose. It accepts
structured focus, traversal, inclusion, input-constraint, and output-limit
parameters. Keyword search is local and lexical; it resolves candidate anchors
rather than pretending to understand intent.

The MVP authoring API separately accepts explicit module names, revision-bound
targets, and ordinary Elixir fragments. It does not ask another model to
reinterpret the agent's intent.

See the complete [context-query contract](QUERY.md).

The [semantic-editing](EDITING.md) MVP creates trustworthy revision-bound
identities while authoring a small managed project. The
[semantic-memory experiment](SEMANTIC_MEMORY.md) persists stable entities,
requested intent, derived facts, and evidence locally. The embedded store is an
operational memory, not the canonical source-code store.

General repository understanding remains the Phase 1 destination. The MVP only
reads files that it created and recorded as managed; it is not a brownfield
importer.

## Local-first guarantee

After installation, every core workflow must run with network access disabled:

- Index a repository
- Create and edit a managed greenfield project
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

They need compact normal-Elixir creation, precise bounded graph slices, stable
identities, visible traversal limits, and unresolved relationships.

### Human reviewers

They need to compare the possible execution paths before and after a change,
including branches, messages, effects, tests, and uncertainty.

### Developers learning or debugging a system

They need to navigate the possible graph and see an observed execution
highlighted within it.

The first MVP serves AI coding agents through semantic authoring. The three
later products remain ordered because each depends on the same graph being
trustworthy.

## MVP foundation

Before Phase 1, 2Ravens runs bounded foundation experiments:

| Foundation | Status | Product question | Primary proof |
| --- | --- | --- | --- |
| Greenfield semantic authoring | Implemented | Can an AI create and safely change a small Elixir system through 2Ravens? | Created source remains ordinary Elixir; derived relationships, minimal edits, qualification, and source-to-graph reconstruction are deterministic. |
| Persistent semantic memory | Implemented; gate failed | Does authoring-time intent and evidence reduce cumulative context across later work? | Semantic memory preserved more facts and correctness but did not beat source indexing on cumulative context. |
| Entity-based batch authoring | Next | Can an agent submit and repair semantic entity changes with materially fewer round trips than file or function-at-a-time authoring? | One cached draft qualifies once, edits exact entities, and projects ordinary source without whole-module merge. |

The foundation remains narrower than the long-term product. It manages only its
own files and supported Elixir subset. The entity API is designed for later
brownfield importing, but comprehensive indexing remains Phase 1 work.

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

The long-term graph represents the complete set of statically knowable
relationships in the repository plus requested intent and observed evidence.
The MVP graph contains only supported facts from 2Ravens-managed files. In both
cases, unsupported or dynamic behavior is represented as unresolved rather than
omitted or guessed.

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

### Semantic candidate

A semantic candidate is an unapplied change against one known repository
revision. It may contain ordinary Elixir for substantial code or a compact
property operation for a small known edit. 2Ravens materializes the candidate
as source, rebuilds the affected graph, and compares the result with the
requested change before it can be applied.

Semantic editing begins as the MVP foundation rather than a fourth product
phase. It establishes the identity, materialization, qualification, and
round-trip boundaries later reused by Phase 1 context and Phase 2 change
projection.

### Observed trace

Phase 3 records one bounded local execution and highlights the actual path
inside the execution envelope. Possible but unobserved paths remain visible.

### Facts and evidence

Persisted facts retain one of three roles:

- Requested knowledge supplied as intent or a claim
- Derived knowledge from source or compiler evidence
- Observed evidence from tests or runtime capture

The complete contract is in
[Authoring-time semantic memory](SEMANTIC_MEMORY.md).

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

- A general-purpose code editor or IDE
- An autonomous coding agent
- An agent harness
- A replacement for Git or GitHub
- A replacement for ExUnit
- A canonical source-code store; semantic candidates materialize ordinary
  source and never replace source or Git authority
- A cloud indexing service
- A general production APM or distributed tracing platform
- A system that requires codebases to add 2Ravens-specific annotations
- A semantic search product based on embeddings or learned reranking

## Planning principles

### Preserve intent, derive facts, and slice them many ways

Requested intent is stored with provenance when the author already knows it.
Definitions, calls, tests, and effects remain derived from source and evidence.
Queries choose focus, directions, relationships, stopping points, constraints,
and limits.

### Derive facts from the system

Callers, effects, process relationships, tests, and ownership should be derived
from code and evidence. When they cannot be derived, show the uncertainty
instead of adding a second declaration that can become stale.

Agents may request changes to editable source-derived properties, but they do
not directly write derived calls, effects, test observations, or evidence.

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

The product plan selects local SQLite only for the bounded semantic-memory
experiment. It does not yet select:

- Tree-sitter or another incomplete-source parser
- An umbrella application structure
- A production UI graph renderer
- A runtime-agent transport
- Production runtime observation

These choices should be made only when a validated workflow creates a concrete
requirement, while preserving the local-first guarantee.
