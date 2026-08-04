Features

2Ravens is a graph-based code understanding and runtime visualization tool for Elixir and OTP.

Its primary users are:

* AI coding agents that need precise repository context
* Human reviewers who need to understand AI-generated changes
* Developers learning or debugging an unfamiliar Elixir application

1. AI Context MCP

The highest-priority feature is an MCP server that allows an AI agent to retrieve the relevant context for a task in one or two calls.

Instead of repeatedly using grep, glob, file reads and symbol searches, the agent queries the code graph.

Primary query

get_change_context(
  target,
  task,
  token_budget
)

The result may include:

* Current behavior summary
* Changed functions and clauses
* Important upstream callers
* Important downstream calls
* Side effects
* OTP processes involved
* Messages sent and received
* GenServer state accessed or changed
* Relevant tests
* Uncovered branches
* Typespecs and documentation
* Architectural boundaries
* Exact source locations
* Dynamic or uncertain relationships

Token-budgeted retrieval

The MCP must rank and compress context based on:

* Relevance to the requested task
* Graph distance
* Changed code
* Public API importance
* Side effects
* Test coverage
* Architectural boundaries
* Available token budget

The goal is not to return the entire dependency graph. The goal is to return the smallest context package that preserves the information needed to make a correct change.

Proposed MCP tools

search_symbols(query)
get_symbol_context(
  symbol,
  direction,
  depth,
  token_budget
)
get_change_context(
  diff | commit | symbols,
  task,
  token_budget
)
get_execution_flow(
  entrypoint,
  target?
)
get_test_coverage(
  symbol | flow
)
get_architecture_context(
  symbol
)

Context freshness

Every response must include index status:

Working-tree revision: current
Changed files indexed: 7/7
Compiled files: 5/7
Provisional source edges: 12
Confirmed compiler edges: 48
Unresolved dynamic calls: 2

This prevents provisional static analysis from being presented as certain.

⸻

2. Static Code Graph

2Ravens continuously builds a semantic graph of the working repository.

Nodes

Possible node types include:

* Application
* Module
* Function
* Function clause
* Pattern
* Guard
* Macro
* Behaviour
* Callback
* Protocol
* Struct
* Test
* Test scenario
* Configuration key
* Supervisor
* GenServer
* Process message
* Source file
* Git commit

Relationships

Possible edges include:

* DEFINES
* CALLS
* CALLED_BY
* MATCHES_CLAUSE
* IMPLEMENTS_CALLBACK
* IMPLEMENTS_PROTOCOL
* USES_STRUCT
* IMPORTS
* ALIASES
* READS_CONFIG
* SENDS_MESSAGE
* HANDLES_MESSAGE
* SUPERVISES
* TESTED_BY
* CHANGED_BY
* GENERATED_BY_MACRO

Each relationship must contain provenance:

Origin:
- source
- compiler
- test
- runtime
Confidence:
- confirmed
- probable
- unresolved

⸻

3. Continuous Working-Tree Indexing

2Ravens must not depend on successful compilation before updating its graph.

AI agents often make broad changes across several files before compiling.

Update flow

File saved
→ filesystem watcher
→ debounce changes
→ tolerant parse
→ replace graph fragment for changed file
→ update impact graph
→ notify MCP and UI

Per-file graph fragments

Each indexed fact includes:

* Source file
* Source range
* File content hash
* File revision
* Parsing origin
* Confidence level

When a file changes, only facts derived from that file are replaced.

Invalid intermediate code

During active editing, files may temporarily be syntactically invalid.

2Ravens should retain:

* Last valid graph fragment
* Current partially parsed symbols
* Explicit stale or uncertain status

Example:

admission.ex is currently incomplete.
Using:
- last valid call relationships
- current module and function boundaries
- provisional changed-symbol detection

A tolerant parser such as Tree-sitter may be used for incomplete working-tree code. Compiler-derived metadata later confirms or corrects the provisional graph.

⸻

4. Change-Impact Review

The static review interface should start with behavior, not files.

For a commit, branch or working-tree diff, show:

* Behaviors affected
* Entry points affected
* Changed function clauses
* Upstream callers
* Downstream side effects
* OTP processes involved
* State changes
* Changed message paths
* Tests covering the affected paths
* Uncovered or uncertain behavior
* Cross-application boundary changes

Example

Behavior changed:
Submit scheduled run
Processes involved:
Scheduler → Admission → Runner
State affected:
Scheduler.in_flight
Changed branches:
- capacity available
- duplicate submission
Coverage:
✓ normal submission
✓ duplicate submission
⚠ runner timeout uncovered

The reviewer expands only the parts requiring deeper inspection.

⸻

5. Progressive Graph Navigation

Files remain the source of truth, but they are not the primary comprehension interface.

The navigation hierarchy should be:

Business or application flow
→ OTP processes
→ Functions
→ Function clauses
→ Test scenarios
→ Runtime examples
→ Source code

Users stop expanding when they have enough confidence to approve or reject the behavior.

Graph abstraction levels

* Domain flow
* Application boundary
* Module flow
* Function flow
* Clause and guard flow
* Runtime execution flow

Low-value implementation details should be collapsed by default.

⸻

6. Function and Clause View

Each function is represented as a graph node.

The node should expose:

* Module, name and arity
* Purpose
* Input shapes
* Output shapes
* Side effects
* Callers
* Callees
* OTP processes involved
* Function clauses
* Guards
* Test coverage
* Concrete execution examples
* Source location

Pattern matching as branches

Elixir function clauses naturally form a decision tree.

def admit(%Run{status: :pending}, %{capacity: n}) when n > 0 do
  ...
end
def admit(%Run{status: :pending}, %{capacity: 0}) do
  ...
end
def admit(%Run{}, _state) do
  ...
end

The graph should render:

admit/2
├─ status=:pending AND capacity>0
│  └─ {:ok, reservation}
├─ status=:pending AND capacity=0
│  └─ {:error, :no_capacity}
└─ other status
   └─ {:error, :invalid_status}

⸻

7. Behavior-Oriented Test Coverage

Line coverage is insufficient for understanding behavior.

2Ravens should map tests to:

* Functions
* Function clauses
* Guard outcomes
* Return shapes
* Call edges
* Messages
* GenServer state transitions
* Side effects
* Assertions

Coverage states

✓ Clause entered and output asserted
◐ Clause entered, guards partially exercised
✓ Downstream call observed
⚠ Side effect occurred but was not asserted
✕ Clause never entered

Test scenario view

Test:
Rejects pending run when capacity is exhausted
Input:
%Run{status: :pending}
%AdmissionState{capacity: 0}
Matched:
admit/2 clause 2
Output:
{:error, :no_capacity}
State changes:
none

Tests become concrete behavioral examples, allowing reviewers to understand a function without immediately reading its implementation.

⸻

8. Manual Function Workbench

Users should be able to execute a function manually when tests are missing or insufficient.

Input generation

Input forms may be derived from:

* Function patterns
* Struct definitions
* Typespecs
* Existing tests
* Fixture factories
* Recorded runtime samples

An advanced raw Elixir term editor should also be available.

Execution result

Show:

* Matched function clause
* Guard results
* Downstream calls
* Return value
* Messages sent
* Side effects
* State changes
* Exceptions

Promote to test

A manually executed scenario can be converted into an ExUnit test.

Uncovered branch
→ provide input
→ execute
→ inspect behavior
→ define expected output
→ save as regression test

Execution must occur in an isolated test environment, not in the active development application by default.

⸻

9. OTP and Supervisor Visualization

2Ravens should represent the application as communicating state machines.

Supervisor tree

Show:

* Supervisors
* Child processes
* Registered names
* Process modules
* Restart strategies
* Process lifecycle
* Restart counts
* Links and monitors

Process highlighting

When debugging a flow:

* Untouched process: neutral
* State read: highlighted
* Message sent or received: highlighted
* State changed: stronger highlight
* Currently executing callback: active animation

Background activity

Visualize:

* Timer events
* Scheduled ticks
* handle_info/2
* Process creation
* Process termination
* Child restarts
* Background jobs

⸻

10. GenServer State View

A GenServer should be presented as an owned state boundary, not literally as a global variable.

For comprehension purposes, it represents persistent process state alongside pure functional dataflow.

State panel

Show:

* State before callback
* Fields read
* Fields changed
* State after callback
* Incoming message
* Matched callback clause
* Reply
* Outgoing messages
* Side effects

Example:

Scheduler
Received:
{:submit, request}
Callback:
handle_call/3 clause 2
State read:
enabled
in_flight
State changed:
in_flight: 2 → 3
Reply:
{:ok, run_id}
Message sent:
{:execute, run_id} → Runner

⸻

11. Attached Runtime Debugging

2Ravens may attach to a running development or test BEAM node.

The user should be able to:

1. Start a scoped capture.
2. Interact with the real application UI.
3. See the resulting execution flow.
4. Inspect messages and process state changes.
5. Copy the complete context.

Example flow

LiveView click
→ handle_event/3
→ Orchestrator.submit/2
→ GenServer.call Scheduler
→ handle_call/3
→ Admission.decide/2
→ Repository.insert/1
→ DynamicSupervisor.start_child/2

Scoped tracing

Tracing the entire BEAM continuously would generate too much data.

Capture scopes may include:

* Next LiveView event
* One HTTP request
* One process tree
* One correlation ID
* Selected modules
* Selected OTP applications
* Until a selected event or error occurs

⸻

12. Runtime Timeline and Replay

Recorded executions should be replayable as a timeline.

Show:

* Function calls
* Messages
* State transitions
* Process lifecycle
* Timer events
* Exceptions
* Supervisor responses

The user should be able to move through an execution event by event and see all synchronized views update.

True arbitrary time-travel mutation is a later capability. The initial implementation should focus on deterministic replay of captured events.

⸻

13. Copy Context

Every important view should provide a copy action.

Available scopes may include:

* Current function
* Current clause
* Selected execution path
* Changed behavior
* Failing test scenario
* Runtime trace
* GenServer state transition
* Complete debugging session

Output formats

* Structured Markdown for humans and AI chats
* JSON for MCP clients and tools

The copied output should contain only the selected subgraph and relevant evidence.

Example:

Issue:
Duplicate scheduled run is admitted.
Flow:
Scheduler.handle_info(:tick)
→ Scheduler.submit_due/2
→ Admission.admit/2
→ RunStore.insert/1
Observed:
duplicate_check/1 returned false
RunStore.insert/1 created a second run
State:
Scheduler.in_flight: 2 → 3
Coverage:
normal path covered
duplicate branch uncovered

⸻

14. Search and Exploration

Users should be able to search by:

* Module
* Function
* Process
* Message
* Behavior
* Test
* Struct
* Config key
* Git commit
* Natural-language intent

Example:

How is a scheduled run submitted?

The result should identify likely entry points and present the relevant graph rather than only a list of matching text.

⸻

15. Explicit Non-Goals

2Ravens is not initially intended to be:

* A code editor
* An autonomous coding agent
* An agent harness
* A replacement for GitHub
* A replacement for ExUnit
* A general production APM platform
* A full distributed tracing platform
* A canonical storage system for source code

Source code, tests and Git remain authoritative. 2Ravens maintains a regenerable understanding index.