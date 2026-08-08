# Local MCP server

2Ravens exposes five focused tools through a project-bound local STDIO server:

- `ravens_discover`: find canonical modules and functions
- `ravens_context`: read exact source-derived context
- `ravens_create_bundle`: create new modules from one Elixir string
- `ravens_change`: apply ordered exact entity edits
- `ravens_retry`: repair a retained malformed request without resending source

MCP is a thin transport over the local Elixir APIs. Source remains authoritative;
returned paths are orientation evidence and never caller-controlled write targets.

## Start the server

Compile before registration so compiler output cannot share the protocol stream:

```powershell
mix deps.get
mix compile
mix ravens.mcp --root C:\code\my_app
```

Register `mix` as the STDIO command, pass `ravens.mcp --root ABSOLUTE_PATH`, and
use the 2Ravens checkout as working directory. The server implements JSON-RPC
`initialize`, `ping`, `tools/list`, `tools/call`, and initialized notifications.
It is bound to one validated root, so tools cannot select another project.

## Discover before guessing

Search names and normal Elixir documentation:

```json
{"query":"delivery promise","limit":10}
```

Use `"query":"*"` for a bounded module listing. Optional `kinds` contains
`"module"`, `"function"`, or both. Matching is deterministic: exact focus,
exact suffix, name prefix, documentation tokens, then canonical focus.
Limits above 20 are safely capped at 20 and reported as a warning, so an
otherwise useful discovery call does not need to be repeated.

Every response contains one `base_revision`. Module results contain canonical
focus, repository-relative path and line, bounded `@moduledoc`, and public
function summaries. Function results contain canonical focus/signature, path,
line, visibility, bounded `@doc`, and derived caller/callee/test counts.
Ambiguity, missing results, suggestions, and truncation remain explicit.

## Read exact context

`ravens_context` accepts canonical function, module, and test focuses:

```json
{"select":[
  {"focus":"function:Shop.Pricing.total/2","include":["source","callers","callees"]},
  {"focus":"module:Shop.Pricing","include":["functions","forms","tests"]}
]}
```

Function fields are `source`, `path`, `clauses`, `callers`, `callees`, `tests`,
`editable`, `docs`, and `evidence`. Module fields are `functions`, `forms`, and
`tests`. Test fields are `source`, `path`, `targets`, `editable`, and `evidence`.

Up to 32 selectors share one source revision and a 64 KB result cap. Whole
function/test source is returned only below its source limit and is never cut
mid-entity. Selector validation and resolution are independent: one malformed,
missing, or oversized selection returns a warning or omitted result without
discarding valid siblings. Missing canonical focuses may include bounded
suggestions.

## Create new modules

Use the flat creation tool when every submitted module is new:

```json
{
  "mode":"apply_if_valid",
  "request_id":"pricing-create-v1",
  "text":"defmodule Shop.Pricing do\n  def total, do: 0\nend",
  "return":[{"focus":"module:Shop.Pricing","include":["functions"]}]
}
```

The tool captures the current revision when `base_revision` is omitted, parses
ordinary Elixir, derives child identities and paths, qualifies once, and applies
atomically. Supply the context revision when creation intentionally depends on a
previous read.

## Edit exact entities

`ravens_change` advertises one flat bounded operation object because nested JSON
Schema alternatives are rendered as generic maps by some MCP clients. Runtime
validation remains strict and operation-specific:

| Operation | Required fields | Optional fields |
| --- | --- | --- |
| create source bundle | `op`, `kind=source_bundle`, `text` | none |
| create function/clause/module form | `op`, `kind`, `parent`, `text` | `before` or `after` |
| replace | `op`, `target`, `text` | none |
| patch | `op`, `target`, `diff` | `hash` |
| set by handle | `op`, `handle`, `value` | none |
| set by field | `op`, `target`, `field`, `value` | none |
| delete | `op`, `target` | `cascade` |
| rename | `op`, `target`, `to` | none |
| move | `op`, `target`, one destination/anchor | another non-conflicting anchor |

The outer request includes `mode` plus either a current `base_revision`, a
retained `draft` and `draft_version`, or an empty managed project. One request
accepts up to 100 operations and 1 MB of submitted source/diff text.

Use `return` to obtain changed source, relationships, module inventories, or
test targets from the accepted revision/draft in the same call. Return selectors
use the same tolerant field rules as context: supported fields are returned with
a warning for unsupported siblings. A selector with no supported field remains
an error, so a mutation cannot silently apply without any requested proof.

A stable bounded `request_id` makes accepted retries idempotent. Exact current
replay returns the original receipt; changed input conflicts; a later accepted
revision makes the old replay explicitly stale.

## Repair without resending source

Every bounded decoded change request is retained before semantic validation.
Validation/application failure returns `attempt`, `attempt_version`, and a
`ravens_retry` repair handle. Apply a small RFC 6902 patch:

```json
{
  "attempt":"attempt:a_123",
  "attempt_version":1,
  "patch":[{"op":"remove","path":"/unexpected"}]
}
```

Supported patch operations are bounded `add`, `remove`, `replace`, and `move`.
Each retry creates an immutable attempt version. Attempts expire after 24 hours,
store strict JSON only, and never mutate accepted semantic state or source.

Unambiguous MCP transport aliases such as `operation` for `op`, or a correctly
matched list of `{path, source}` records, normalize to the canonical source
bundle. Paths are checked against module-derived paths and never used directly.

Qualification failures occur after a candidate exists and continue to return a
`needs_changes` draft. Patch only the failing function, clause, module form, or
test in that draft. Applying a ready draft omits operations:

```json
{"draft":"draft:d_123","draft_version":1,"mode":"apply_if_valid"}
```

## Completion evidence

An applied MCP receipt adds:

```json
{
  "status":"applied",
  "verification_complete":true,
  "next_action":"none",
  "proof":{
    "format":"pass",
    "compile":"pass",
    "tests":"pass",
    "source_read_back":"pass",
    "graph_comparison":"pass",
    "semantic_persistence":"pass"
  }
}
```

No post-change context or shell test is needed when requested returned evidence
and this proof cover the task.

## Local benchmark metrics

Set `TWO_RAVENS_METRICS_FILE` to an absolute JSONL path to record local metadata:
call/request/result/source byte counts, repeated source bytes, selectors,
qualifications, elapsed time, status, and error code. The sink is opt-in, writes
no source or source hashes, performs no network access, and never changes product
behavior if unavailable.
