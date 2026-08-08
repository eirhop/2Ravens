# Development scope 03 — Entity-based batch authoring MVP

## Status

First vertical slice implemented; completion gate not yet met.

The current implementation provides strict ordered requests, multi-module
source bundles, exact function/clause/module-form operations, versioned SQLite
drafts for qualification failures, one qualification per batch, atomic
managed-path materialization, and `mix ravens change`/`draft-context` local CLI
transport. The focused integration suite exercises these paths across separate
CLI processes and through the decoded-map MCP adapter.

The following scope requirements remain explicit gaps:

- Requests that fail operation application before qualification return a
  structured error but are not yet retained as repairable drafts.
- Typed literal `set` handles are not exposed; only comparison operators and
  module documentation are supported.
- Function rename and cross-module move block when callers exist instead of
  rewriting statically proved call sites.
- Rename/move persistence does not yet guarantee stable database entity IDs
  when fingerprint reconciliation is ambiguous.
- Cascade receipts count children but do not enumerate their identities;
  relationship deltas are not populated.
- Script and top-level-form editing remain unimplemented.
- The reproducible live-agent probe and comparative measurements required by
  the completion gate have not been run.

Scope 01 proved safe managed source materialization. Scope 02 implemented local
semantic memory in commit `83630db`, but its frozen lifecycle gate remained
unfavorable against source-indexed cumulative context. A live Luna authoring
probe then demonstrated correct semantic creation while exposing excessive
command round trips, repeated qualification, Windows standard-input friction,
and discarded invalid submissions.

This scope tests the accepted [entity authoring API](../ENTITY_AUTHORING.md).
It is a new authoring workflow hypothesis, not a retroactive favorable reading
of the earlier benchmarks.

## Outcome

Deliver one runnable vertical slice in which a caller can:

1. Submit one JSON-shaped request containing ordered entity operations.
2. Create several entirely new ordinary Elixir modules from one source bundle.
3. Add, replace, patch, set, delete, rename, and move managed entity children
   without submitting an existing module or file.
4. Treat multiple clauses as ordered children of one function identity.
5. Retain an invalid large request as a versioned SQLite draft.
6. Repair only the invalid entity and commit without resending the original
   source bundle.
7. Qualify once and atomically materialize conventional source projections.
8. Query accepted and draft entities through compact semantic identities.

The first implementation remains manifest-managed. Its entity API and source
projection rules must be compatible with a later brownfield importer, but this
scope does not index arbitrary unmanaged repositories.

## Public API

Add one thin public facade:

```elixir
TwoRavens.Change.submit(root, request)
```

It returns:

```elixir
{:ok, %TwoRavens.Change.Receipt{}}
{:error, %TwoRavens.Change.Error{}}
```

A valid request whose candidate needs repair returns an `:ok` receipt with
`status: :needs_changes`, a draft ID/version, compact operation-scoped
diagnostics, and no working-tree changes. Malformed public arguments, unsafe
roots, stale draft versions, and unavailable projects return structured errors.

Add a transport adapter that accepts the decoded JSON-shaped map intended for a
future `ravens_change` MCP tool and delegates to the same facade. A small local
CLI may submit the identical JSON through standard input or a request file. Do
not build a general MCP server in this scope.

## Request contract

Validate the exact keys, duplicates, types, and operation-specific fields from
[Entity authoring API](../ENTITY_AUTHORING.md). Unknown fields fail.

The minimum envelope is:

```elixir
%{
  "base_revision" => "r_...",
  "commit" => "if_valid",
  "operations" => [%{"op" => "..."}]
}
```

Draft repair replaces `base_revision` with `draft` and `draft_version`. A
request cannot provide both. `operations` is always a non-empty list and is
bounded by count and total source bytes.

Implement `commit` values `if_valid` and `draft_only`. No operation stages or
commits Git changes.

## Required entity representation

Extend the source/domain graph without conflating stable semantic entities with
file ranges:

- module owns documents, module forms, functions, clauses, and tests
- function owns its documentation/specification bundle and ordered clauses
- clause retains stable ID, ordinal, fingerprint, patterns, guard, calls,
  comparisons, source range, and source fragment
- source projection maps accepted entities to one managed path and revision
- call/test relationships remain source-derived

Parse and preserve normal `@moduledoc`, `@doc`, and `@spec`. Do not add custom
annotations or accept intent/relation/risk/invariant fields in the new API.

## Required operations

### Creation

- `create kind=source_bundle`: accept multiple complete new `defmodule` forms,
  reject any collision, split one top-level module per new projection, and
  derive all child identities and relationships.
- `create kind=function`: target one existing managed module and accept exactly
  one function name/arity with one or more clauses.
- `create kind=clause`: target one existing function, require matching
  name/arity/kind/visibility, and require a resolvable `before` or `after` anchor
  when placement is ambiguous.
- `create kind=module_form`: target one module and accept one valid module-body
  form. Preserve unknown macro semantics explicitly.

### Exact replacement and patch

- `replace` one function, clause, module document, or module form. Replacing a
  function replaces its complete bundle and all clauses. Reject complete
  existing-module replacement.
- `patch` one entity or draft fragment with exact context and current hash.
  Implement a bounded unified-diff subset sufficient for one or more exact
  hunks; reject fuzzy or repository-wide matching.
- `set` continues the existing comparison-operator handle and adds typed module
  documentation and supported literal values without becoming arbitrary AST
  mutation.

### Lifecycle changes

- `delete` a function, clause, module form, or empty module. Module cascade must
  be explicit and report every child.
- `rename` a managed function or module while preserving stable entity ID and
  rewriting only statically proved references.
- `move` a function between managed modules or reorder a clause using exact
  anchors while preserving stable identity.

If a later operation in the same request targets an entity created or renamed
earlier, resolve it against the current draft graph. Any unsupported dynamic
reference blocks an automatic rewrite and remains visible.

## Draft persistence

Add a forward-only schema migration for versioned draft state. Store only bound
values through the semantic-store boundary. The minimum persisted fields are:

- draft ID and version
- project/base semantic revision and working hash
- status and bounded expiry
- ordered validated operation payloads
- candidate entity/source fragments and hashes
- structured diagnostics and qualification summary

Do not keep a SQLite transaction or connection open while a draft awaits an
agent. A repair creates a new immutable draft version. Commit verifies the
draft version and base hashes immediately before source effects.

Draft deletion/expiry is recoverable local cleanup and never removes accepted
source or semantic revisions.

## Projection rules

For new modules, materialize one path derived from the module name and order:

1. module documentation
2. directives and module forms
3. public entry functions before their callees
4. private helpers after public functions

Keep all clauses contiguous and preserve dispatch order. For recursive function
groups, preserve submission order with semantic-key tie-breaking.

For existing managed modules, preserve all unrelated bytes and sibling order.
Insert a new whole function at a deterministic caller/callee boundary, but do
not globally reorder existing functions. Explicit clause/form anchors override
default placement.

## Candidate and commit pipeline

One request produces one immutable candidate:

```text
validate request and operations
-> synchronize accepted store/source
-> load accepted entity graph
-> apply operations sequentially in memory
-> parse and derive candidate graph
-> cache draft version
-> isolated format, read-back, compile, and tests
-> if invalid: persist diagnostics and return needs_changes
-> if valid and draft_only: return ready draft
-> if valid and if_valid: verify base hashes
-> short SQLite transaction plus atomic source projection writes
-> read back source and compare semantic signatures
-> commit or restore every source byte and roll back
```

Never persist accepted semantic facts for a draft that has not committed.

## Compact receipts

Successful default output contains only:

- status, operation count, and draft/revision identity
- entity counts by action and kind
- derived relationship delta counts
- qualification summary and test count
- affected managed paths count, not full source

Failure output identifies operation index, entity/fragment, source range when
available, structured reason, and whether the working tree changed. Full source,
diff, and provenance remain explicit opt-ins.

## Suggested code boundaries

```text
TwoRavens.Change                    thin public facade
TwoRavens.Change.Request            envelope validation
TwoRavens.Change.Operation          discriminated operation validation
TwoRavens.Change.Engine             pure sequential draft transformation
TwoRavens.Change.Draft              versioned domain value
TwoRavens.Change.Receipt            compact public result
TwoRavens.Change.Error              structured public error
TwoRavens.Change.SourceBundle       multi-module parsing and splitting
TwoRavens.Change.Projector          entity-to-module source projection
TwoRavens.Change.Patch              exact bounded entity patching
TwoRavens.SemanticStore.Drafts      persistence through store facade
TwoRavens.MCP.Change                decoded-map transport adapter only
```

Keep parsing, graph derivation, request validation, operation application, and
projection pure. Filesystem, subprocess, and SQL effects stay in their existing
boundaries. No change-domain module calls Exqlite directly.

## Checkpoints

1. **Request:** validate one ordered operation list and return structured errors.
2. **Bundle:** split two new modules from one text and dry-run one candidate.
3. **Entity:** add and replace one function without submitting its module.
4. **Clauses:** query, insert, replace, delete, and reorder one clause safely.
5. **Batch:** apply several dependent operations sequentially and qualify once.
6. **Draft:** persist a failed batch, repair one entity in a new process, and
   commit without resending original fragments.
7. **Lifecycle:** delete, rename, and move while preserving or retiring stable
   identities and reporting unresolved references.
8. **Transport:** round-trip the documented JSON-shaped map through the MCP
   handler and compact receipt.
9. **Probe:** reproduce the prior Epic 1 feature with materially fewer agent
   operations and no direct application-source access.

Each checkpoint leaves Scope 01 and Scope 02 tests passing.

## Out of scope

- General unmanaged brownfield repository indexing or watching
- A full STDIO/HTTP MCP server or plugin packaging
- Custom macros, source annotations, or a `.ravens` programming language
- Caller-supplied relations, intent, risk, or invariant metadata
- Whole-existing-module merge or replacement
- Automatic global brownfield function reordering
- Arbitrary non-Elixir file editing
- General compiler macro expansion or claimed semantics for unknown DSLs
- Concurrent draft writers, portable draft synchronization, or Git operations
- UI or graph visualization

## Test strategy

Add focused unit and integration tests for:

- strict envelope and discriminated-operation validation
- multiple new modules from one source bundle and collision rollback
- one function with several ordered clauses and stable child IDs
- exact parent/target resolution across earlier operations in one batch
- create/replace/patch/set/delete/rename/move success and failure
- ambiguous clause placement, shadowing diagnostics, and contiguous projection
- module-document and generic module-form child editing
- no whole-existing-module merge or implicit deletion by omission
- draft persistence, version staleness, expiry, repair, and fresh-process reuse
- base-source drift between draft creation and commit
- dry-run byte immutability and failed-qualification isolation
- multi-path atomic write, SQLite failure rollback, and byte-verified restoration
- accepted source read-back graph/signature equality
- no caller-supplied structural relations or unsupported semantic claims
- compact receipts and detailed opt-in output
- real Windows-safe transport-handler invocation without relying on PowerShell
  pipeline exit semantics

## Required verification

Run and report compactly:

```text
mix format
mix compile --warnings-as-errors
MIX_ENV=test mix compile --warnings-as-errors
mix test --no-compile
mix credo --strict
mix dialyzer
mix sobelow --private
mix xref graph --format cycles
git diff --check
```

Add a recorded agent probe using one bundled request plus any repair requests.
Measure task correctness, total model input/cached input/output when available,
tool calls, operation count, returned context bytes, qualification count, and
direct-source-access violations. Do not claim savings without a comparable
files-only or prior-probe baseline.

## Completion gate

Status: not yet met.

This scope is complete when:

- The decoded JSON-shaped API executes ordered entity operations through one
  public Elixir facade.
- New free-form source is decomposed only when every submitted module is new.
- Every edit to existing code targets exactly one entity or ordered child.
- No merge or complete replacement of an existing module exists.
- Invalid large requests remain repairable without resending accepted source.
- Qualification happens once per submitted or repaired candidate, not once per
  individual operation.
- Clauses preserve Elixir dispatch order and are independently queryable and
  editable.
- Source files are conventional projections and accepted source/store state
  remains transactionally consistent and recoverable.
- The Epic 1 live-agent probe is reproducible through materially fewer authoring
  calls without lowering correctness.

If these guarantees require direct graph-row mutation, hidden source rewrites,
or a custom language, stop and revise the design instead of weakening them.
