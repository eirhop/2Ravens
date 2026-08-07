---
name: two-ravens-elixir-patterns
description: Apply 2Ravens' repository-specific Elixir patterns when implementing or reviewing authoring, managed-file safety, source parsing, graph construction, qualification, context, CLI, or benchmark changes. Use this skill to keep public APIs small, evidence honest, source authoritative, and side effects recoverable.
---

# 2Ravens Elixir Patterns

Use these patterns for new code and refactors. Preserve `{:ok, value}` and
`{:error, reason}` at ordinary API boundaries and keep source plus Git as the
recoverable authorities.

## Start at the dependency boundary

Place stable semantic identity and evidence constructors below both source
parsing and graph assembly. Keep dependencies directed:

```text
identity and domain values
        |
source loading -> parsing -> fact extraction
        |
graph assembly and queries
        |
authoring operations -> qualification -> materialization
        |
CLI adapters
```

Keep `TwoRavens.Authoring` and `TwoRavens.Source` as thin public facades. Put
operation-specific logic in focused modules. Run `mix xref graph --format
cycles` after changing layer boundaries and remove every cycle.

## Treat managed paths as capabilities

Normalize an untrusted relative path once with `TwoRavens.ManagedPath`. Resolve
it again at every read or write boundary through `TwoRavens.Project`.

- Reject absolute paths, parent traversal, invalid extensions, and null bytes.
- Walk existing path components and reject symbolic links or reparse points.
- Apply the same containment rule to internal management metadata.
- Never construct a writable absolute path with an unchecked `Path.join/2`.
- Revalidate immediately before each side effect; do not rely on an earlier
  check performed during parsing.

Add a real symlink or junction escape test for every new writable path class.

## Build immutable candidates before applying

Use this pipeline:

```text
validate input
-> parse ordinary Elixir
-> derive candidate graph
-> build immutable proposal
-> dry-run result or isolated qualification
-> verify manifest and source hashes
-> atomically write ordinary files
-> rebuild accepted graph
-> compare semantic signatures
-> return applied result
```

Use operation-specific evidence profiles. Creation dry-runs may stay in memory
as `:unqualified_dry_run`, with compile and tests marked `:not_run`. The MVP
semantic `set` dry-run uses `:qualified_dry_run`: qualify it in a disposable
project, report compile and test results, and leave the real project unchanged.

For `apply: true`, format in a disposable project, rebuild and compare the
formatted graph, compile with warnings as errors, and run tests. Check base
hashes only after qualification and immediately before the real write.

Snapshot every affected source and the manifest before writing. Use
same-directory atomic file replacement. On any returned post-write failure,
restore and byte-verify the snapshot. Return `:rollback_failed` with both the
original and rollback failures when recovery cannot be proven.

## Require evidence before rendering a claim

Represent evidence with fixed structs and explicit states such as `:pass`,
`:not_run`, or `%{status: :unknown, reason: reason}`.

- Derive calls, tests, and graph edges from managed source only.
- Fail duplicate semantic identities with their source locations; never let
  `Map.put/3` silently choose a winner.
- Do not infer behavior from a literal appearing somewhere in a related file.
- Render only statically proved boundary truth. Prove fallback compatibility
  only from supported adjacent clauses with equal patterns and a guard that is
  true at the boundary. Report exact boundary-test evidence absent only after
  uniquely locating the guarded parameter and deriving supported constant
  arithmetic through graph-confirmed, one-clause passthrough calls. Any
  unsupported, unresolved, or conditional execution flow makes the result
  unknown.
- Keep unsupported syntax, ambiguity, stale handles, and missing evidence
  visible in both APIs and CLI output.

## Separate fact producers

Keep these responsibilities independently testable:

- loader: read only manifest-managed files and candidate substitutions;
- parser: turn one valid Elixir module into deterministic domain values;
- subset validator: disclose unsupported syntax without guessing semantics;
- fact extractor: derive calls and editable comparisons;
- range helper: construct exact repository-relative source locations;
- graph: validate unique identities, assemble edges, and traverse relationships.

Use one file per public domain struct. Prefer pure functions in the parser,
extractor, graph, and candidate builder. Keep filesystem reads inside
`Project`, `Manifest`, `Source.Loader`, and explicit unmanaged-collision
discovery. Keep writes and subprocess effects inside `Manifest`, `Qualifier`,
and `Materializer` boundaries.

## Validate public inputs once

Validate keyword keys, duplicates, defaults, and value types before project
access. Unknown or malformed options must return structured errors rather than
being ignored or raising a function-clause exception. Keep the Mix task limited
to argument parsing, stdin, API calls, and presentation.

## Verify the whole pattern

Add focused tests for the changed pure behavior plus integration tests for its
side-effect boundary. For authoring changes, prove dry-run byte immutability,
failed-qualification isolation, stale rejection, linked-path confinement,
post-write rollback, accepted graph equality, and a new-process reconstruction.

Instrument benchmarks from recorded events. Use identical timing endpoints and
clearly define input, author-facing output, qualification output, tool-call, and
subprocess counts. Keep unavailable token metrics unavailable and state an
unfavorable result plainly.
