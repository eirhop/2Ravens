# Development scope 04 — Agent authoring ergonomics and lossless recovery

## Status

Implemented; first paired lifecycle passed, replication gate open.

The final frozen three-job Luna lifecycle completed correctly with zero repair
calls and zero repeated submitted-source bytes. Against files, Ravens used
48.4% fewer total tokens, 45.5% fewer wrappers, and 38.4% less wall time. The
[full record](../../benchmarks/entity_authoring/lifecycle_luna_2026-08-08.md)
keeps the divergent test counts and remaining discovery cost explicit. Repeat
the paired lifecycle before making a general scaling claim.

Scope 03 proved that entity-based authoring, qualification, atomic projection,
semantic persistence, and real MCP transport work. Its three-job Luna lifecycle
also showed that the ideal path can beat ordinary files, but that namespace
guessing, opaque client-visible schemas, discarded malformed requests, and
coarse test repair make ordinary mistakes too expensive.

This scope fixes that agent boundary. It does not replace SQLite, add a graph
database, invent a source language, or weaken source authority.

## Outcome

Deliver a local agent workflow in which a fresh model can:

1. Discover canonical modules and functions from names or documentation.
2. See repository-relative module paths, module docs, function docs, and compact
   source-derived relationship counts before choosing an entry function.
3. Create any number of new modules through one flat source-bundle tool.
4. Edit an existing function, clause, module form, or test through one exact
   entity operation.
5. Preserve a large syntactically valid request before semantic validation and
   repair it without resending its source.
6. Receive useful results for valid selectors even when one sibling selector is
   malformed or missing.
7. Treat an applied receipt as complete qualification evidence without a
   redundant context or shell verification round trip.

## Root causes addressed

- MCP clients may collapse nested JSON Schema combinators into generic maps.
- Exact graph focuses are efficient after discovery but poor discovery inputs.
- Strict validation currently discards the most expensive request content.
- Tests exist in the graph but are not complete editable entity targets.
- Instructions cannot reliably compensate for an opaque or unforgiving API.

## Public boundaries

Keep source and Git authoritative. Paths returned by discovery are orientation
evidence and never caller-controlled write targets.

Expose focused public facades backed by the existing graph and Change engine:

```elixir
TwoRavens.Discovery.query(root, request)
TwoRavens.Change.submit(root, request)
TwoRavens.Change.retry(root, request)
```

The MCP adapter exposes five single-purpose tools:

- `ravens_discover`
- `ravens_context`
- `ravens_create_bundle`
- `ravens_change`
- `ravens_retry`

Schemas at this boundary stay flat and bounded. Conditional operation rules
remain strict in Elixir validation instead of nested `oneOf`/`anyOf` schemas.

## Discovery contract

`ravens_discover` accepts a required bounded `query`, optional bounded `limit`,
and optional kinds. `*` lists the bounded namespace. Matching is deterministic:

1. exact canonical focus
2. exact module or function suffix
3. name prefix
4. documentation token match
5. canonical focus tie-breaker

Module summaries include canonical focus, repository-relative path and start
line, bounded `@moduledoc`, and bounded public function summaries. Function
summaries include canonical focus, signature, path and line, visibility,
bounded `@doc`, and derived caller, callee, and related-test counts. Every
response binds to one current base revision and reports truncation explicitly.

Search is local and deterministic. No embeddings, network services, or invented
entry-point semantics are introduced.

A positive requested limit above the supported maximum is clamped with an
explicit warning. Invalid types and non-positive limits still fail. This avoids
a discovery retry without weakening the response bound.

## Flat creation and change contracts

`ravens_create_bundle` accepts ordinary Elixir once:

```json
{
  "mode": "apply_if_valid",
  "request_id": "epic-5",
  "text": "defmodule Shop.A do\nend\n\ndefmodule Shop.B do\nend",
  "return": []
}
```

It translates to the existing `create kind=source_bundle` operation. An
optional base revision binds it to previously read context; otherwise the
server captures the current revision and verifies it again immediately before
materialization.

`ravens_change` retains ordered entity operations but advertises one flat
operation object containing the bounded union of known fields. Runtime
validation remains operation-specific and rejects unknown or contradictory
fields.

## Lossless request attempts

Every bounded decoded-map payload that passes minimal type and size checks is
captured before full semantic validation. An invalid payload returns a short
attempt ID/version plus structured diagnostics. It never changes source or
accepted semantic state.

Attempts are immutable, versioned, bounded, expiring SQLite values stored
through the semantic-store facade with strict JSON serialization. A bounded
RFC 6902 patch creates the next attempt version. The caller sends only the
patch, not the retained source.

Safe MCP-only normalization may translate an unambiguous transport mistake to
the canonical request. Supplied file paths are never write capabilities:
2Ravens parses module source, derives projection paths, and rejects a claimed
path that conflicts with the derived path.

Candidate qualification failures continue to use Scope 03 drafts. Request
attempts cover failures before a candidate draft exists.

## Test entity editing

An existing `test:` focus supports bounded source, target relationships, source
path, and exact patch/replace/delete operations. A body-only edit preserves the
test identity. A renamed test may receive a new semantic identity.

New test modules continue to arrive through `source_bundle`. Accepted existing
modules remain unavailable as whole-module replacement targets. A module first
created inside an uncommitted draft may be replaced as draft content when that
is required for recovery.

Deleting and recreating one module/path in an ordered draft is valid. Internal
deletion tombstones must not be mistaken for live module collisions, while
base hashes, rollback snapshots, and materialization remain unchanged.

## Context and errors

Selector validation and resolution are independent. One malformed, missing, or
oversized selector returns an omitted result without discarding valid siblings.
Errors include allowed fields, bounded canonical suggestions, and a copy-ready
correction or retry payload where one is safe.

Context and return selectors keep supported fields when unsupported fields are
also requested and attach a correction warning. A selector with no supported
field remains invalid.

Applied receipts explicitly state that formatting, warnings-as-errors compile,
tests, source read-back, graph comparison, and semantic persistence completed.
Requested return selections bind to the accepted revision or retained draft.

## Instrumentation

An opt-in local benchmark event sink records metadata only:

- tool and operation counts
- request, source, and result byte counts
- repeated submitted source bytes
- selector failures and corrections
- attempt and draft repair counts
- qualification and materialization counts
- status and structured error code

It stores no source, prompts, secrets, or telemetry and performs no network
access.

## Implementation checkpoints

1. Freeze the exact Epic 4 and Epic 5 failure traces as regressions.
2. Publish flat MCP schemas and prove their real client-visible shape.
3. Add deterministic discovery with paths and documentation.
4. Make context selector failures independent and suggest canonical focuses.
5. Capture malformed request attempts and retry them with a small patch.
6. Add exact test selection/editing and same-draft path recreation.
7. Tighten receipts, tool descriptions, and benchmark AGENTS guidance.
8. Run the full quality matrix and the unchanged paired Luna lifecycle.

## Required tests

- deterministic exact, suffix, prefix, and documentation discovery
- bounded `*` namespace listing and explicit ambiguity/truncation
- no invented docs or entry-point claims
- no public MCP schema combinators that collapse to generic maps
- real fresh-process list/call behavior for every tool
- one invalid selector preserving all valid siblings
- an 8 KB source request repaired without resending source
- attempt migration idempotency, expiry, corruption handling, and fresh-process
  reuse
- test source selection and one-assertion draft repair
- same-draft delete plus recreate at one managed path
- failed validation, qualification, and retry byte immutability
- accepted graph/source/store equality and post-write rollback

## Required verification

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

## Completion gate

Correctness and final tests must match the paired files condition. The same
three frozen jobs must use no direct application-source access and retransmit no
large source. Normal creation uses one bundle call; an existing edit uses at
most one discovery/context round plus one change; a qualification failure needs
at most one small repair.

After a diagnostic pass, run at least three paired fresh-agent lifecycles. The
scope may claim an efficiency win only when median cumulative model input is at
least 10% below files, cumulative authoring calls are lower, and no individual
Ravens job is more than 25% worse. Keep an unfavorable result explicit.
