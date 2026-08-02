# Vision

## The problem

Software development is changing.

AI is rapidly becoming capable of producing entire codebases.

The bottleneck is no longer writing code.

The bottleneck is understanding it.

Humans can no longer rely on memorizing an entire codebase when AI continuously generates and refactors thousands of lines of code.

Today's development tools are still built around reading files, searching text, navigating symbols and interpreting logs.

That workflow does not scale.

## Vision

2Ravens is a graph-based understanding layer for Elixir and OTP.

It allows both humans and AI to understand software through behavior rather than source files.

Instead of asking:

- Which file changed?

Users should ask:

- What behavior changed?
- Which execution flow is affected?
- Which OTP processes participate?
- Which state changes?
- Which tests verify this behavior?

## Core principles

Source code remains the source of truth.

Files are an implementation detail.

The primary interface should be behavior, execution flow and architecture.

Progressive disclosure is preferred over exposing implementation immediately.

Users should only drill down until they understand enough.

## Static understanding

Build a semantic graph from source code.

Examples:

- Modules
- Functions
- Clauses
- Pattern matching
- Guards
- Call graph
- Behaviours
- Protocols
- Supervisor tree
- GenServers
- Message types
- Tests
- Documentation
- Git history

## Runtime understanding

Attach to a running BEAM application.

Visualize:

- Supervisor tree
- Process lifecycle
- Messages
- State transitions
- Background timers
- Live execution
- Runtime traces
- Process restarts

Users should be able to click around their application and watch execution flow through the graph.

## Function understanding

Functions become executable graph nodes.

Each function should expose:

- Purpose
- Inputs
- Outputs
- Side effects
- Pattern-matched branches
- Example executions
- Tests
- Coverage
- Downstream effects

Users should be able to execute functions manually to understand behavior without writing tests first.

Successful scenarios can be promoted directly into ExUnit tests.

## OTP understanding

OTP is the primary abstraction.

The application should be visualized as communicating state machines.

The UI should make it easy to understand:

- Processes
- Messages
- State ownership
- Supervision
- Restarts
- Timers

rather than merely source files.

## AI-first context

One of the primary goals is reducing AI exploration.

Instead of dozens of grep, glob and file-open operations, an AI should retrieve relevant context in one call.

Example:

```
get_change_context(
    symbol,
    task,
    token_budget
)
```

The response should contain only the relevant execution graph, tests, state, architecture and source.

This reduces:

- Tool calls
- Tokens
- Hallucinations
- Missing dependencies

while increasing precision.

## Human-first review

Review should become behavior-oriented.

Instead of reading diffs first, reviewers should see:

- Changed behavior
- Affected flows
- Changed branches
- Tests
- State changes
- OTP processes
- Runtime impact

Source code should be the deepest layer, not the first.

## Knowledge sharing

Everything visible in the UI should be copyable.

Users should be able to copy:

- Function context
- Execution flow
- Runtime trace
- State transitions
- Review context

and paste directly into an AI conversation.

The copied context should contain exactly the information necessary to solve the problem.

## Hugin & Munin

2Ravens consists of two primary concepts.

### Munin

Memory.

Responsible for:

- Graph index
- Synchronization
- Storage
- Incremental updates
- Relationships

### Hugin

Thought.

Responsible for:

- MCP
- Graph queries
- Visualization
- AI context generation
- Human understanding

## Long-term vision

The ultimate goal is to replace file-oriented understanding with graph-oriented understanding.

Humans should navigate software the same way they navigate maps.

AI should reason over semantic relationships instead of reconstructing architecture through repeated text searches.

2Ravens aims to become the understanding layer for Elixir and OTP applications in the AI era.