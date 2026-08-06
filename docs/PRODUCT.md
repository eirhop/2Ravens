# Product plan

## Product thesis

2Ravens turns repository and runtime evidence into the smallest useful
explanation for the current task.

Its semantic graph is a shared foundation, not the primary user experience:

```text
Source + compiler + tests + Git + runtime observations
                         ↓
                Semantic evidence graph
                         ↓
                 Task-oriented projections
                  ├── AI context
                  ├── Change review
                  └── Exploration and debugging
```

The product grows through three sequential phases. Phase 1 proves that the
graph can retrieve useful context. Phase 2 uses the same facts to make code
review faster. Phase 3 adds scoped runtime evidence so people can explore and
explain real executions.

## Target users

### AI coding agents

They need precise, bounded repository context with clear source locations,
freshness, and uncertainty.

### Human reviewers

They need to understand changed behavior, affected flows, tests, boundaries,
and risk without reconstructing the system from a diff.

### Developers learning or debugging a system

They need to see how functions, OTP processes, messages, state, and supervision
participate in a concrete behavior.

The users are related, but they are served in that order. Trying to serve all
three before Phase 1 is proven would hide whether the foundation is useful.

## The three phases

| Phase | Product promise | Primary proof |
| --- | --- | --- |
| [1. AI context](phases/01-ai-context.md) | Return the smallest trustworthy context needed for a task. | Agents complete real tasks with less exploration and no loss of correctness. |
| [2. Behavior-first review](phases/02-behavior-review.md) | Explain what a change does and what it can affect. | Reviewers understand changes faster and find important risks or gaps. |
| [3. Runtime understanding](phases/03-runtime-understanding.md) | Make an unfamiliar system explorable and a concrete execution explainable. | Developers can trace and explain real behavior through functions, processes, messages, and state. |

Each phase has an explicit gate. Later phases may be researched, but product
development should not move through a gate until the previous promise has been
validated.

## Shared product model

### Facts and evidence

A graph fact may have several evidence records:

```text
CALLS relationship
├── source parser: probable
├── compiler: confirmed
├── test capture: observed
└── runtime capture: observed
```

Every fact must retain:

- Origin
- Confidence
- Source or event location
- Repository revision or runtime session
- Freshness
- Any unresolved or inferred portion

Evidence may strengthen a relationship, but stronger evidence must not erase
its provenance.

### Task-oriented projections

Users should rarely see the complete graph. Products should request a
projection such as:

- Change context
- Symbol context
- Affected flow
- Test evidence
- Process context
- Runtime session

Ranking and compression are product behavior. They must be deterministic enough
to evaluate and transparent enough to debug.

### Source materialization

The graph stores relationships and source references. Exact source must be read
from the relevant repository revision when constructing a response or view.
The graph must not become a stale canonical copy of source code.

## Product-wide non-goals

2Ravens is not intended to become:

- A code editor
- An autonomous coding agent
- An agent harness
- A replacement for Git or GitHub
- A replacement for ExUnit
- A canonical source-code store
- A general production APM or distributed tracing platform

Some integrations may connect to those products, but 2Ravens remains focused on
understanding.

## Planning principles

### Plan outcomes before implementation

Before starting a phase, document its user, promise, workflow, scope, risks,
validation method, and exit criteria.

### Keep technical decisions reversible

Storage engines, parser fallbacks, UI renderers, and runtime transports should
be selected from evidence gathered in the phase that needs them. They are not
product commitments.

### Build one complete workflow before broad capability

A narrow end-to-end result is more useful than many disconnected extractors or
views. Each phase starts with one representative task and expands only after it
works.

### Prefer grounded facts over generated confidence

Summaries and explanations must point back to evidence. A plausible narrative
without inspectable support is a product failure.

### Validate against real work

Benchmarks should use representative changes, reviews, and failures from a
substantial Elixir system. Synthetic examples are useful for deterministic
tests but insufficient for product validation.

## Decisions intentionally deferred

The product plan does not yet select:

- A persistent graph database
- Tree-sitter or another incomplete-source parser
- An umbrella application structure
- A production UI graph renderer
- A runtime-agent transport
- Production runtime observation
- Vector or language-model-assisted ranking

These choices should be made only when a validated workflow creates a concrete
requirement.
