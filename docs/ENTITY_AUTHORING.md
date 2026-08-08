# Entity authoring API

## Status

Accepted API direction with a working first vertical slice. See
[Development scope 03](scopes/03-entity-authoring-mvp.md) for implemented
behavior, qualification evidence, and the remaining completion gaps.

This contract supersedes the file-shaped editing direction for new authoring
work. Scope 01 and Scope 02 remain evidence for safe source materialization,
stable identity, persistence, provenance, and rollback.

## Purpose

An AI should create and change Elixir entities, not edit their packaging files.
2Ravens stores stable module, function, clause, and module-form identities,
derives their relationships, and projects accepted entities into ordinary
formatted Elixir files.

```text
AI request -> entity draft -> derived graph -> projected source
-> formatter/compiler/tests -> atomic source and semantic-memory commit
```

Source and Git remain recoverable authorities. The database is the local
operational model at one verified source revision; it is not a hidden runtime
or an alternative language implementation.

## Core decisions

- One request may contain an ordered list of operations.
- Operations run sequentially against one cached draft and commit atomically.
- Free-form ordinary Elixir is accepted when every submitted module is new.
- Existing code is edited only through exact entity targets.
- Existing modules never accept a whole-module merge.
- Omitting a child entity never deletes or changes it.
- Function clauses are ordered child entities of one function name and arity.
- Call, ownership, test, type, behaviour, and other derivable relationships
  come from source and evidence; the agent does not submit them.
- `@moduledoc`, `@doc`, and `@spec` provide searchable source documentation.
- The API adds no custom macros, `ravens_intent`, risk labels, invariants, or
  duplicated relationship declarations.
- Files are projections. New modules default to one top-level module per file;
  imported brownfield packaging remains unchanged unless explicitly moved.

## Entity model

The minimum ownership model is:

```text
project
└── module
    ├── module document
    ├── directive or generic module form
    ├── type, callback, struct, or attribute
    ├── function
    │   ├── function document and specification
    │   └── ordered clause
    └── test
```

Minimum editable entity kinds are:

- `module`
- `module_document`
- `module_form`
- `function`
- `clause`
- `test`
- `script`
- `top_level_form`

`module_form` is the honest escape boundary for valid Elixir forms such as
`alias`, `import`, `require`, `use`, behaviours, structs, types, callbacks, and
framework macro DSLs that do not yet have a more precise domain type. Unknown
semantics remain explicit even when the form compiles.

A function identity is module, name, arity, definition kind, and visibility.
Its documentation, specification, attributes, and all clauses form one
replaceable function bundle. A clause has its own stable ID, structural
fingerprint, patterns, guard, source fragment, and ordinal within the function.

Calls normally target the function identity. A call-to-clause relation is
derived only when supported static evidence proves or bounds compatible
clauses. Passing tests remain revision evidence and do not prove clause
coverage.

## Public request envelope

The transport-neutral request is JSON-shaped and maps directly to one future
MCP tool named `ravens_change`:

```json
{
  "root": ".",
  "base_revision": "r_42",
  "commit": "if_valid",
  "operations": [
    {"op": "create", "kind": "function", "parent": "module:Shop.Pricing", "text": "..."},
    {"op": "replace", "target": "function:Shop.Total.calculate/1", "text": "..."}
  ]
}
```

The `operations` value is always a list, including for one operation. This
keeps one schema, permits atomic batching without changing shape, and costs
negligible input compared with source text.

Operations execute in list order. Later operations see earlier draft changes.
They never observe a partial working-tree apply.

`base_revision` binds the request to the source/store revision. It is required
for edits and optional only when initializing an empty managed project.

`commit` supports:

- `"if_valid"`: qualify and commit in the same request when every operation is
  valid; otherwise retain a repairable draft.
- `"draft_only"`: validate and cache without touching the working tree.

To repair a retained draft, use the same request shape with `draft` and its
current version:

```json
{
  "root": ".",
  "draft": "d_73",
  "draft_version": 1,
  "commit": "if_valid",
  "operations": [
    {"op": "patch", "target": "function:Shop.Pricing.total/2", "diff": "..."}
  ]
}
```

## Operations

### `create`

Create identities that do not exist. A collision is an error; `create` never
silently replaces source.

For a greenfield bundle, omit `parent` and submit one or more complete new
`defmodule` forms:

```json
{
  "op": "create",
  "kind": "source_bundle",
  "text": "defmodule Shop.Catalog do\n  ...\nend\n\ndefmodule Shop.Pricing do\n  ...\nend"
}
```

2Ravens splits the bundle into module, document, form, function, clause, and
test entities, derives relationships, and projects one conventional file for
each new top-level module. If any submitted module exists, the operation fails
without merging.

Add one function to an existing module:

```json
{
  "op": "create",
  "kind": "function",
  "parent": "module:Shop.Pricing",
  "text": "@doc \"Returns the discount in cents.\"\n@spec discount(non_neg_integer(), non_neg_integer()) :: non_neg_integer()\ndef discount(amount, rate), do: div(amount * rate, 100)"
}
```

The text must contain one function name and arity, with one or more clauses.
Add one clause with an explicit order anchor when dispatch order matters:

```json
{
  "op": "create",
  "kind": "clause",
  "parent": "function:Shop.Pricing.discount/2",
  "before": "clause:c_fallback",
  "text": "def discount(amount, :partner), do: div(amount * 8, 100)"
}
```

`before` and `after` are mutually exclusive. Without an anchor, 2Ravens may
place a whole new function by its projection policy, but it must not guess an
ambiguous clause or order-sensitive module-form position.

Module-level source such as an alias is another child entity:

```json
{
  "op": "create",
  "kind": "module_form",
  "parent": "module:Shop.Pricing",
  "text": "alias Shop.DiscountPolicy"
}
```

### `replace`

Replace exactly one existing child entity:

```json
{
  "op": "replace",
  "target": "function:Shop.Pricing.discount/2",
  "text": "@doc \"Returns a capped discount.\"\ndef discount(amount, rate), do: div(amount * min(rate, 50), 100)"
}
```

Replacing a function replaces its complete documentation/specification/clause
bundle. Replacing a clause preserves its function siblings. Replacing a module
with a complete `defmodule` is not part of this API; edit module-owned fields and
children explicitly.

### `patch`

Apply a bounded textual patch to one entity fragment or retained draft
fragment. The patch is not file-relative and cannot touch entity siblings.

```json
{
  "op": "patch",
  "target": "function:Shop.Pricing.discount/2",
  "diff": "@@\n- min(rate, 50)\n+ min(rate, 40)"
}
```

The current entity or draft hash is part of patch resolution. Missing or
ambiguous context fails instead of applying a fuzzy repository-wide match.

### `set`

Change one typed property exposed by a revision-bound edit handle:

```json
{"op": "set", "handle": "h_maximum_discount", "value": 40}
```

Initial typed targets remain intentionally narrow: supported literals,
comparison operators, and module documentation. `set` is an efficiency helper,
not a general graph mutation API.

### `delete`

Delete exactly one entity:

```json
{"op": "delete", "target": "function:Shop.Pricing.legacy_discount/1"}
```

Deleting a module with active children requires an explicit cascade and reports
all affected identities. Callers, dispatch gaps, compilation failures, and test
effects remain visible diagnostics.

### `rename`

Change the semantic name while preserving the stable entity ID:

```json
{
  "op": "rename",
  "target": "function:Shop.Pricing.final_price/2",
  "to": "function:Shop.Pricing.discounted_price/2"
}
```

2Ravens rewrites only statically proved references. Dynamic or ambiguous
references remain unresolved and may block commit.

### `move`

Change an entity parent while preserving stable identity:

```json
{
  "op": "move",
  "target": "function:Shop.Pricing.discount_rate/1",
  "to": "module:Shop.DiscountPolicy"
}
```

Moving an ordered clause within its current function uses `before` or `after`.
Moving a module-form or function across modules updates both projections and
only the references that can be proved safe.

## Module-owned editing

An existing module is never a file-shaped merge target. Its own editable data
is deliberately small:

- canonical module name through `rename`
- `@moduledoc` through a typed `set` or exact document child target
- directives and generic module forms through child `create`, `replace`, and
  `delete`
- packaging path through an explicit move only when required

Runtime entry points are functions and use function operations. Function docs,
specifications, attributes, and clauses belong to their function child, not to
the module entity.

## Draft lifecycle

An invalid large request is retained instead of discarded:

```text
submit -> cache draft d_73 version 1 -> parse/graph/qualify
       -> success: short atomic commit
       -> failure: compact diagnostics and unchanged working tree

repair d_73 version 1 -> apply entity operations -> d_73 version 2
                      -> revalidate -> commit or retain again
```

Draft storage is normal short-lived SQLite state, not an open SQL transaction.
It stores the base revision, ordered operations, accepted fragment text,
diagnostics, status, version, and expiry. The final source/store transaction is
opened only after qualification and immediate base-hash verification.

Drafts are immutable by version. A repair creates the next version. Stale draft
versions, changed base source, missing targets, or expired drafts fail
explicitly. Draft context may be queried without materializing working-tree
source. Drafts expire after a bounded local retention period and may be
discarded explicitly.

## Projection and ordering

New top-level modules default to one conventional file per module. A new module
projection orders source as:

1. module documentation
2. directives, behaviours, attributes, structs, types, and callbacks
3. public entry functions
4. functions in caller-before-callee hierarchy
5. private helpers

All clauses of one function remain contiguous and preserve semantic dispatch
order. Recursive strongly connected function groups preserve submitted order,
then use semantic key as a deterministic tie-breaker.

Existing brownfield sibling order is preserved by default. Adding or replacing
one entity must not reorder unrelated entities. A later explicit normalization
operation may offer hierarchy sorting after its review cost is measured.

## Documentation and metadata

Searchable meaning comes from normal Elixir constructs:

- `@moduledoc` states module responsibility, domain concepts, units, and
  exclusions.
- `@doc` states observable function behavior, inputs, outputs, units, errors,
  and important boundaries.
- `@spec`, types, behaviours, callbacks, patterns, guards, calls, and tests
  provide structured source-derived facts.

Documentation should use stable domain language, not keyword stuffing. Private
functions remain searchable by identity, source, callers, callees, patterns,
and tests even when public documentation does not apply.

Additional metadata is not accepted until a concrete consumer requires a fact
that cannot be derived and does not belong in source documentation. In
particular, the API has no caller-supplied relation, risk, invariant, or intent
field.

## MCP boundary

MCP is transport only. The first implementation exposes a decoded-map handler
with the same validation and return values as the public Elixir API. A local
STDIO server may later map its `tools/call` request directly to that handler
without redefining operations.

Large Elixir remains one string per entity operation. The JSON envelope contains
only operation identity and safety fields. Context queries and mutation
receipts stay compact and never return the whole draft unless requested.

## Required safety behavior

- Validate every public field before project access.
- Resolve semantic targets and managed paths at every side-effect boundary.
- Build one immutable candidate from the ordered operations.
- Preserve the working tree on malformed input, unsupported entities,
  qualification failure, stale base, or failed draft repair.
- Format, parse, rebuild, compile with warnings as errors, and test in an
  isolated project before apply.
- Verify base hashes immediately before the real write.
- Atomically write every affected projection and manifest entry.
- Read source back, rebuild the graph, compare accepted semantic signatures,
  and commit SQLite only when they agree.
- Restore and byte-verify every affected source on returned post-write failure.
- Return explicit unknown or unsupported diagnostics rather than invented
  relationships or safe rewrite claims.

## Deliberate non-goals for the first API

- Arbitrary agent-written macros or 2Ravens source annotations
- Caller-supplied graph edges, intent, risk, or invariant metadata
- Whole-existing-module merge or implicit deletion by omission
- Direct database, SQL, AST-record, or file-record mutation
- Automatic reordering of unrelated brownfield entities
- A long-running database transaction while an agent repairs a draft
- General non-Elixir file editing
- Hidden Git staging, commits, branches, or pushes
