# Phase 3 — Runtime understanding

## Status

Planned. Product development begins after the static evidence and review
workflows have proved useful.

## Product promise

Make an unfamiliar Elixir system explorable and overlay one concrete execution
or failure on the possible graph so it is explainable through functions, OTP
processes, messages, state, and supervision.

## Why this is valuable

Important Elixir behavior often crosses process boundaries. Call graphs alone
cannot explain asynchronous messages, timers, state ownership, process
lifecycle, or supervisor responses.

Developers currently reconstruct that behavior from source, logs, traces,
process inspection, and prior knowledge. Phase 3 combines those observations
with the possible execution graph so a human can see both what could have
happened and what actually occurred.

This supports two related jobs:

- **Explore:** build a mental model of an unfamiliar system.
- **Debug:** explain a specific execution, state transition, error, or restart.

## Target user

The initial user is a developer working with a local development or test BEAM
application. Production observation is a separate later decision with a much
higher security and operational bar.

## Primary workflows

### Explore a system

1. Search for a behavior, function, process, message, or application.
2. See the relevant possible execution envelope and OTP relationships.
3. Identify supervisors, processes, callbacks, messages, and state owners.
4. Follow relationships into tests, runtime examples, and source.
5. Copy the selected system context.

### Debug one interaction

1. Select a narrow capture scope.
2. Perform one application action or run one test.
3. See the observed function and process path highlighted inside the possible
   execution envelope.
4. Inspect messages and relevant state transitions.
5. Inspect exceptions, process exits, and supervisor responses.
6. Overlay observed events on the static graph.
7. Replay and export the grounded debugging context.

## Required capabilities

### Static OTP model

Extend the static graph where evidence supports:

- Supervisors and child specifications
- GenServer callbacks
- Registered processes
- Message send and handling relationships
- Timers and background callbacks
- Links, monitors, and restart strategies
- Likely state ownership

Static relationships must remain distinguishable from observed runtime
relationships.

### Scoped capture sessions

Every runtime capture must define:

- Trigger
- Process and module scope
- Correlation metadata
- Maximum duration
- Maximum event count and queue size
- Value capture and redaction policy
- Expected observation overhead

Possible event sources include Telemetry, Erlang trace sessions, process
monitoring, supervisor introspection, `:sys` facilities, Logger metadata, and
explicit instrumentation. The implementation should use the narrowest source
that can answer the selected question.

### Runtime evidence

A session may record:

- Function execution
- Message sends and receives
- GenServer callback entry and result
- Relevant state before and after a callback
- Process creation and termination
- Links and monitors
- Timer events
- Exceptions and exits
- Supervisor restart behavior

Captured values must be normalized, bounded, and redacted before storage or
display.

### Possible-versus-observed overlay

Observed events attach to the same function, clause, call-site, message,
process, state, and effect nodes used by the static graph.

The UI should distinguish:

- Possible and unobserved paths
- The observed path
- Static relationships contradicted or unresolved by the observation
- Runtime events with no resolved static node

An observed path confirms that one execution occurred. It does not prove that
unobserved paths are impossible.

### Timeline and replay

A recorded session should be replayable event by event. The graph, process
view, state panel, and source location should stay synchronized with the
selected event.

Replay means deterministic navigation through captured evidence. Arbitrary
time-travel mutation is not required.

### Causal explanation

Asynchronous systems do not always have a single call stack. 2Ravens must
distinguish:

- Confirmed synchronous relationships
- Confirmed message send and receive relationships
- Process parent, link, and monitor relationships
- Temporal or correlation-based relationships
- Inferred causality
- Unknown causality

The UI must never present temporal proximity alone as proven causation.

## Delivery milestones

### 1. Static system explorer

- Add the OTP facts required to understand one representative system.
- Search and navigate processes, callbacks, messages, and supervision.
- Reuse the progressive UI and evidence views from Phase 2.

### 2. Test capture

- Capture one bounded ExUnit scenario.
- Overlay observed function entries and messages on the static graph.
- Show the matched clauses and relevant state transitions where safe.

### 3. Attached development session

- Attach explicitly to a local development node.
- Capture one selected UI action, request, or process interaction.
- Show process lifecycle, messages, state changes, errors, and restarts.

### 4. Timeline and explanation

- Replay the captured session event by event.
- Highlight the observed path inside the possible execution envelope.
- Generate a grounded explanation linked to evidence.
- Copy the complete debugging context for a human or AI.

### 5. Product evaluation

- Select representative unfamiliar-system and debugging tasks.
- Compare existing tools with the 2Ravens workflow.
- Improve capture scope and explanation before considering broader tracing.

## Safety and operational constraints

Runtime observation may expose credentials, personal information, business
data, authentication tokens, and internal file paths. It can also alter the
timing of the system being observed.

Phase 3 therefore requires:

- Development and test use by default
- Complete local operation without an account, API key, or hosted collector
- Explicit attachment and capture start
- Local binding and authentication by default
- Bounded sessions, queues, values, and source scopes
- Backpressure, sampling, or dropping policies
- Redaction and structural value limits
- Visible tracing mode and overhead warnings
- No mutation of captured production state

Native or external runtime components must remain replaceable and must not put
the target BEAM at unnecessary risk.

## Validation

Use real workflows from a substantial OTP system:

- Learn which processes implement an unfamiliar behavior.
- Follow one request or UI action across process boundaries.
- Explain a state-dependent failure.
- Explain an exception and supervisor response.
- Identify an untested or unobserved path.

Measure:

- Time to a correct system explanation
- Time to identify the cause of a failure
- Important processes, messages, and state transitions found
- Incorrect causal claims
- Amount of raw log and source inspection required
- Runtime overhead and dropped events
- Developer confidence supported by inspectable evidence

## Risks

- Observation can change timing and hide or create failures.
- Event volume can overwhelm the collector and the user.
- State and messages can contain sensitive information.
- Distributed or asynchronous behavior may have uncertain causality.
- A runtime agent can destabilize the target application.
- A general explorer can become a collection of views without a clear workflow.

The first runtime slice must remain scoped to one interaction and one question.

## Non-goals

Phase 3 does not initially include:

- Unrestricted global tracing
- Continuous production monitoring
- A general production APM platform
- Full distributed tracing across arbitrary systems
- Arbitrary time-travel mutation
- Editing live process state
- Claiming complete causality where the evidence is incomplete

## Exit criteria

Phase 3 is complete when a developer unfamiliar with a representative system
can:

- Identify the important processes, messages, and state owners for a behavior.
- Capture one bounded development or test interaction.
- Follow its function, process, message, and state timeline.
- See the actual path inside the possible paths.
- Explain a real failure and supervisor response from inspectable evidence.
- Distinguish confirmed observations from inferred causality.
- Export the complete relevant context for another human or AI.

Passing this gate realizes the initial full product path. Production-safe
observation, distributed systems, and architecture rules remain separate
opportunities that require their own validation.
