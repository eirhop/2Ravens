# Context query

## Purpose

An AI agent often knows what it wants to understand but spends many operations
finding definitions, callers, effects, tests, process relationships, and source.

2Ravens exposes one flexible operation over the prebuilt repository graph:

```text
context(
  focus,
  traversal,
  include,
  constraints,
  limit
)
```

The agent interprets the user's task. The query contains explicit graph needs,
not open-ended task prose.

## Interfaces

The product has one core operation with thin adapters:

```text
MCP tool ───┐
Mix task ───┼→ TwoRavens.Context → repository graph
Elixir API ─┘
```

The initial user-facing forms are:

```text
Mix task:   mix ravens
MCP server: two_ravens
MCP tool:   context
```

The Mix task is the first development and diagnostic interface. The local
STDIO MCP server is the preferred agent interface once the contract is stable.
Both must call the same Elixir API and return the same logical response.

## Focus

`focus` contains one or more graph anchors.

Initial focus types:

- Repository
- Application
- Module
- Function
- Function clause
- File or source range
- Working-tree change
- Commit or diff
- Test
- Struct or type
- Exact local keywords
- A node ID returned by an earlier query

Later graph layers add processes, messages, state fields, runtime sessions, and
events without changing the overall query shape.

Examples:

```text
focus: module Favn.Admission
focus: function Favn.Admission.admit/2
focus: working_tree
focus: keywords ["duplicate", "scheduled", "run"]
focus: [function A.run/1, function B.retry/1]
```

Keyword focus uses deterministic local matching over identifiers, names,
ordinary documentation, typespecs, test names, file paths, and source text. It
does not use embeddings or a semantic model. If several candidates are
plausible, the response returns them as ambiguous instead of selecting one
silently.

## Traversal

Traversal specifies how to move through the graph:

```text
direction: upstream | downstream | both
max_depth: non-negative integer
max_nodes_per_hop: positive integer
max_total_nodes: positive integer

relations:
- defines
- calls
- invokes_macro
- expands_to
- dataflows_to
- sends
- handles
- implements
- uses
- supervises
- tested_by
- reads
- writes

stop_at:
- public_entrypoint
- side_effect
- application_boundary
- process_boundary
- external_dependency
```

Depth and width are explicit safety limits. Meaningful stopping points and
relationship types are the main way to request precise context.

A raw neighborhood is useful for orientation. For behavior, 2Ravens should
prefer paths such as:

- Public entry point → focus
- Focus → side effect
- Test → focus
- Sender → message → handler
- Handler → state transition
- Focus → application boundary

## Included material

`include` controls which node and edge details are materialized:

- Ordinary documentation
- Typespecs and contracts
- Exact source
- Function clauses
- Patterns and guards
- Argument and result mappings
- Tests
- OTP messages and handlers
- Evidence, confidence, and uncertainty

The graph always retains these facts when indexed. `include` controls response
cost, not truth or traversal semantics.

## Input constraints

Optional constraints narrow an execution envelope:

```text
argument 1 is a %Run{status: :pending}
argument 2 has capacity greater than zero
```

2Ravens uses abstract values rather than executing arbitrary code:

- Unknown
- Known literal
- Struct or map shape
- Possible atom set
- Numeric range
- Known tuple shape
- Known keys

It can eliminate clauses and branches that are incompatible with known
patterns and guards. When an expression cannot be evaluated statically, the
result remains unknown and all compatible paths remain possible.

## Multi-focus queries

A multi-focus query returns one combined subgraph, not concatenated context for
each focus.

2Ravens should:

1. Traverse from every focus.
2. Record which focus reaches each node.
3. Find common upstream and downstream relationships.
4. Find meaningful paths connecting the focus nodes.
5. Merge identical nodes and shared path segments.
6. Materialize each source range, document, and test once.
7. Separate shared and focus-specific context.

The default combination is a deduplicated union with shared relationships
grouped and prioritized. Later explicit modes may include:

- `union` — all requested context, deduplicated
- `shared` — common upstream and downstream relationships
- `connect` — the smallest meaningful paths connecting focus nodes
- `compare` — shared context plus what is unique to each focus

Commonality alone does not imply importance. Standard-library utilities and
generic high-fan-in helpers should normally be collapsed. Repository-owned
entry points, effects, tests, boundaries, and nearby connecting paths are more
useful shared context.

If the focus nodes are unrelated within the traversal limits, return separate
components and say so rather than manufacturing a connection.

## Limit and context packing

`limit` bounds response size using a deterministic local unit such as UTF-8
bytes or characters. Model-specific tokenization is not required.

Pack context in this order:

1. Focus nodes
2. Paths connecting focus nodes
3. Shared entry points and effects
4. Other shared dependencies
5. Focus-specific required context, balanced across focuses
6. Supporting context while space remains

Never truncate half a function or hide known uncertainty. If required context
cannot fit, return that condition explicitly.

## Response

Every query returns the same logical shape:

```text
Status
Resolved focus
Graph nodes and typed relationships
Important paths
Shared context
Focus-specific context
Selected source
Evidence and confidence
Unresolved relationships
Unexpanded frontier
Repository and index freshness
Output cost
```

Each included item explains its structural reason, for example:

```text
Included because:
- direct caller of Favn.Admission.admit/2
- lies on a path from a public entry point
- crosses into persistence
```

The unexpanded frontier reports hidden scope:

```text
Scheduler has 6 unexpanded upstream relationships.
RunnerSupervisor has 14 unexpanded downstream relationships.
```

The agent can call `context` again using a returned node ID. No separate
`expand` tool is required.

## Progressive usage scenarios

### Unfamiliar repository

```text
focus: repository
depth: 1
include: applications, public entry points
```

Continue with the selected application or module.

### Module orientation

```text
focus: module Favn.Admission
direction: both
depth: 1
include: docs, public functions, behaviours, tests
```

Continue with the relevant function returned by the first query.

### Known function change

```text
focus: function Favn.Admission.admit/2
upstream: until public entry point
downstream: until side effect
include: clauses, guards, argument mappings, tests, source
```

### Vague issue

```text
focus: keywords ["duplicate", "scheduled", "run"]
depth: 1
```

Select a candidate node and request its execution envelope.

### Refactor several functions

```text
focus: [function A.run/1, function B.retry/1]
direction: both
stop_at: [public entry point, application boundary, side effect]
include: contracts, call sites, tests, unresolved calls
```

The result merges common callers, dependencies, effects, tests, documentation,
and source.

### Failing test

```text
focus: test "rejects duplicate active run"
direction: downstream
include: clauses, guards, calls, effects
```

Later test capture can overlay the observed path on the possible graph.

### Input-sensitive behavior

```text
focus: function Favn.Admission.admit/2
constraints:
- argument 1 status is pending
- argument 2 capacity is greater than zero
downstream: until side effect
```

Repeat without the capacity constraint to reveal both capacity paths.

### OTP interaction

```text
focus: module Favn.Scheduler
relations: [supervises, sends, handles, calls, reads, writes]
depth: 2
```

Continue with a selected message handler or state transition.

### Working-tree impact

```text
focus: working_tree
direction: both
stop_at: [public entry point, side effect, application boundary]
include: changed clauses, tests, source, uncertainty
```

Phase 2 renders the same before-and-after graph projection for human review.

## Initial boundary

Do not begin with a general graph query language such as Cypher. A small typed
schema is easier for agents to discover, validate, and use correctly.

The initial contract should be validated through hand-written expected results
for representative scenarios before implementation.
