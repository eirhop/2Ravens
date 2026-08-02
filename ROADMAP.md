Roadmap

The roadmap prioritizes the immediate value of precise AI context retrieval and static human review.

Runtime debugging is built only after the static graph proves useful.

Phase 0 — Research and technical spikes

Goals

Validate the uncertain technical foundations before building the product shell.

Spikes

* Parse Elixir modules, functions, clauses, patterns and guards.
* Identify explicit local and remote calls.
* Evaluate Tree-sitter support for incomplete Elixir files.
* Capture compiler metadata using tracers and mix xref.
* Test embedded SurrealDB through Rust and Rustler.
* Measure graph traversal latency.
* Capture function execution and clause coverage in ExUnit.
* Inspect supervisor trees and GenServer state safely.
* Test isolated Erlang trace sessions.

Exit criteria

* A small Elixir project can be represented as nodes and edges.
* One changed file can be incrementally re-indexed.
* A symbol context query returns relevant callers, callees and tests.
* Storage choice is supported by measured evidence.

⸻

Phase 1 — Munin static index

Goal

Continuously maintain a useful graph of the working repository without requiring compilation.

Features

* Filesystem watcher
* Change debounce and coalescing
* Content hashing
* Tolerant source parsing
* Per-file graph fragments
* Modules and functions
* Function clauses
* Patterns and guards
* Explicit calls
* Aliases and imports
* Behaviours and callbacks
* Tests
* Source ranges
* HEAD and working-tree snapshots
* Index freshness reporting

Exit criteria

* Saved file changes appear in the graph quickly.
* Broad uncompiled edits are visible.
* Invalid intermediate files do not destroy the last valid graph.
* Changed symbols can be calculated from the working tree.

⸻

Phase 2 — AI Context MCP

Goal

Reduce repository exploration from many shell operations to one or two structured calls.

Features

* Symbol search
* Symbol context
* Upstream and downstream traversal
* Change context
* Architecture context
* Test context
* Source materialization from current files
* Relevance ranking
* Token budgets
* Context freshness and uncertainty
* Structured Markdown and JSON output

Initial MCP tools

search_symbols
get_symbol_context
get_change_context
get_execution_flow
get_test_coverage
get_architecture_context

Evaluation

Run representative Favn coding tasks with and without 2Ravens.

Measure:

* Number of tool calls
* Input tokens
* Time to first correct edit
* Missed dependencies
* Incorrect assumptions
* Number of follow-up context requests

Target outcome

Tool calls:
15–25 → 1–3
Context:
150–200k → 30–60k tokens

These are hypotheses, not guaranteed results.

Exit criteria

* Agents consistently use get_change_context.
* Returned context includes the important files and relationships.
* Context size is materially smaller than manual repository exploration.
* Agent accuracy is not degraded.

⸻

Phase 3 — Static review UI

Goal

Allow humans to understand changes through behavior and flows rather than files.

Features

* Repository overview
* Symbol search
* Function graph
* Clause and guard tree
* Git change overlay
* Affected flow view
* Test mapping
* Uncovered branch highlighting
* OTP process relationships inferred from source
* Source drill-down
* Copy current context

Initial review workflow

Open working-tree change
→ see changed behavior
→ inspect affected flow
→ inspect changed branches
→ inspect tests
→ open source only where necessary

Exit criteria

A reviewer can answer these questions without manually searching the repository:

* What behavior changed?
* What calls this code?
* What does it call?
* Which process owns the relevant state?
* Which tests cover the changed branches?
* What remains uncertain?

⸻

Phase 4 — Test behavior graph

Goal

Turn tests into concrete examples attached to functions and clauses.

Features

* Test execution capture
* Function entry tracking
* Clause coverage
* Guard outcome coverage
* Return-shape capture
* Call-edge coverage
* Message capture
* State transition capture
* Assertion association
* Value normalization and redaction
* Scenario replay

Exit criteria

For a selected function, the UI can show:

* Its clauses
* Tests exercising each clause
* Example inputs
* Expected outputs
* Uncovered branches
* Side effects that were not asserted

⸻

Phase 5 — Manual function workbench

Goal

Allow users to understand uncovered functions by executing them safely.

Features

* Generated input forms
* Struct-aware inputs
* Raw Elixir term input
* Matched-clause display
* Guard results
* Return values
* Downstream calls
* Exceptions
* Isolated execution
* Temporary database transaction support
* Side-effect controls
* Save scenario as ExUnit test

Exit criteria

A user can select an uncovered clause, provide input, inspect the result and generate a regression test.

⸻

Phase 6 — OTP process visualization

Goal

Present the application as a system of supervised communicating processes.

Features

* Supervisor tree
* Registered processes
* Process lifecycle
* Links and monitors
* Restart strategies
* Message definitions
* GenServer callback graph
* Timer and tick relationships
* Static state ownership view

Exit criteria

A user unfamiliar with the codebase can identify:

* Which processes exist
* Who supervises them
* What messages they handle
* What state they own
* Which application flows involve them

⸻

Phase 7 — Attached runtime sessions

Goal

Trace one selected interaction through a live development or test application.

First vertical slice

Use a concrete Favn flow such as:

Click “Submit run”
→ LiveView event
→ Orchestrator
→ Scheduler GenServer
→ Admission
→ Persistence
→ RunnerSupervisor

Features

* Runtime attachment
* Scoped capture sessions
* Live supervisor tree
* Function execution overlay
* Message send and receive
* GenServer state before and after
* Child process creation
* Timer events
* Exceptions and restarts
* Session timeline
* Copy runtime context

Exit criteria

The user can:

1. Start capture.
2. Click an application UI action.
3. See the resulting process and function flow.
4. Inspect relevant state changes.
5. Copy the captured context for an AI.

⸻

Phase 8 — Replay and causal explanation

Goal

Help users understand why runtime behavior occurred.

Features

* Event-by-event replay
* Synchronized graph and state panels
* Message lineage
* Process lifecycle replay
* Supervisor restart explanation
* Error-path extraction
* “Why did this happen?” context generation
* Confirmed versus inferred causality

Exit criteria

For a recorded failure, 2Ravens can produce a grounded explanation containing:

* Trigger
* Function path
* Process messages
* State transitions
* Failure
* Supervisor response
* Relevant source and tests

⸻

Phase 9 — Advanced capabilities

Potential later features:

* Historical graph comparisons
* Architecture boundary rules
* Automatic detection of undesirable dependencies
* Runtime versus static graph drift
* Suggested missing tests
* Test generation from manual sessions
* Distributed BEAM visualization
* Cross-node message flow
* Production-safe sampled observation
* Semantic search
* Vector-assisted context ranking
* Architecture documentation generation
* Hot-code upgrade visualization

These should not be prioritized until the core MCP and review workflows demonstrate clear value.

⸻

Product validation principles

Every phase should be measured against actual user problems.

AI value

* Fewer repository exploration calls
* Lower token usage
* Better dependency recall
* Fewer incorrect edits
* Faster task completion

Human value

* Faster review orientation
* Better understanding of affected behavior
* Easier identification of missing tests
* Less source code that must be read
* Greater confidence reviewing AI-generated changes

Runtime value

* Faster identification of process and state interactions
* Less dependence on interpreting raw logs
* Easier understanding of supervisor behavior
* Reproducible captured debugging sessions

⸻

Immediate next milestone

The first deliverable should be deliberately narrow:

Given one changed Elixir function, return a precise graph-based context package containing its clauses, important callers, important callees, relevant tests, application boundaries and exact source ranges.

Deliver this through both:

* One MCP tool
* One basic visual graph

Everything else builds on that foundation.