# Vision

## The problem

AI is making software faster to produce, but not easier to understand.

As codebases grow and change more quickly, the bottleneck moves from writing
code to answering questions such as:

- What behavior changed?
- Which execution flows are affected?
- Which OTP processes participate?
- What state can change?
- Which tests provide evidence for the behavior?
- What remains uncertain?

Current tools make people and AI reconstruct those answers from files, text
searches, diffs, logs, and process inspection. That work is slow, repetitive,
and easy to get wrong.

## The vision

2Ravens is an understanding layer for Elixir and OTP systems.

It builds a semantic evidence graph from source code, compiler information,
tests, Git, and scoped runtime observations. It then presents task-oriented
answers and views rather than exposing the complete graph.

The graph is not the product. The product is faster, more trustworthy
understanding.

Source files remain available as the deepest level of evidence, but users
should be able to begin with behavior, execution flow, state ownership, tests,
and architecture.

## The product path

2Ravens reaches the vision through three sequential phases.

### Phase 1 — AI context

Give an AI agent the smallest trustworthy context needed to complete a task.
The agent should spend less time searching the repository and be less likely to
miss important callers, tests, boundaries, or side effects.

### Phase 2 — Behavior-first review

Help a human understand what a code change does and what it can affect before
reading every line of the diff. Review should move from changed behavior to
affected flows, evidence, uncertainty, and finally source.

### Phase 3 — Runtime understanding

Help a human explore an unfamiliar OTP system and explain a concrete execution
or failure. Static relationships and observed runtime events should form one
grounded account of functions, processes, messages, state transitions, errors,
and supervisor responses.

Each phase must be useful on its own and must prove the foundation needed by the
next phase.

## Core principles

### Authority remains outside 2Ravens

Source code, tests, Git, and runtime events are authoritative. The graph is a
derived, disposable projection that can be rebuilt.

### Evidence must be visible

Every relationship must identify where it came from. Source-derived,
compiler-confirmed, test-observed, runtime-observed, and inferred relationships
must not be presented as equivalent.

### Uncertainty is part of the answer

Elixir permits macros, dynamic dispatch, generated code, and asynchronous
behavior. 2Ravens must show incomplete, stale, unresolved, or inferred
information instead of hiding it.

### Start with the user's question

Raw graphs quickly become overwhelming. 2Ravens should return opinionated
projections for a task, change, behavior, process, or debugging session.

### Use progressive disclosure

Begin with a concise explanation. Let the user move through behavior, flows,
processes, functions, clauses, tests, runtime evidence, and source only as far
as needed.

### Human and AI understanding share one foundation

The MCP response, review UI, runtime explorer, and copied context should be
different views over the same evidence model.

### Runtime observation is scoped and safe

Tracing must be explicit, bounded, and development/test-oriented by default.
2Ravens must disclose uncertainty, sensitive-value handling, and the risk that
observation changes timing.

### Product value must be measured

Every phase must improve a real task. A sophisticated graph that does not make
agents or humans more effective is not success.

## Hugin and Munin

The project uses two conceptual names:

- **Munin — memory:** indexing, synchronization, evidence, provenance, and graph
  retrieval.
- **Hugin — thought:** context selection, explanation, MCP, visualization, and
  human workflows.

They describe responsibilities. They should become separate applications only
if implementation experience demonstrates a useful boundary.

## Long-term destination

An AI should be able to request grounded repository context without rebuilding
the architecture through repeated searches.

A reviewer should be able to understand the behavioral effect of a change
before reading its implementation in detail.

A developer should be able to perform one action, follow it through an OTP
system, inspect relevant state changes, and explain why the result occurred.

2Ravens succeeds when understanding an Elixir system becomes closer to
navigating a map than assembling a story from disconnected files and logs.
