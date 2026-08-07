# Implementation prompt — Greenfield semantic authoring MVP

Copy the prompt below into a development task from the root of the 2Ravens
repository.

```text
Implement the first 2Ravens MVP in this repository.

Before changing code, read and follow:

1. AGENTS.md
2. docs/scopes/01-greenfield-authoring-mvp.md
3. docs/EDITING.md
4. docs/ARCHITECTURE.md
5. docs/QUERY.md

Treat docs/scopes/01-greenfield-authoring-mvp.md as the authoritative delivery
scope. If another document describes the later brownfield Phase 1, do not expand
this MVP to implement that later scope.

Goal

Build the complete greenfield semantic-authoring vertical slice. Starting with
an ordinary new Mix project, 2Ravens must initialize small management metadata,
create two modules and several functions from normal Elixir input, derive their
call and test relationships, return compact function context, dry-run one
revision-bound comparison-operator edit, qualify it in isolation, apply it
explicitly, and rebuild an equal graph from the resulting source.

Important boundaries

- Keep source and Git recoverable authorities.
- The graph is an in-memory projection rebuilt from 2Ravens-managed files on
  every CLI command.
- Read only paths recorded as managed; do not build a brownfield importer.
- Accept normal Elixir through standard input for substantial additions.
- Derive calls, tests, and impact; never accept asserted graph edges.
- Default authoring operations to dry-run and require --apply for writes.
- Keep the Mix task thin over ordinary documented Elixir APIs.
- Use immutable structs and maps; keep side effects at explicit boundaries.
- Return consistent {:ok, value} / {:error, reason} shapes.
- Report unsupported syntax, stale handles, ambiguity, and missing evidence
  honestly.
- Do not add a database, ETS, daemon, file watcher, MCP server, UI, umbrella,
  custom language, or unrelated edit operations.
- Do not stage, commit, or push unless explicitly asked.

Execution

Implement the scope checkpoint by checkpoint and keep a runnable path after
each checkpoint:

1. Initialize a disposable Mix project safely.
2. Create and read back one module.
3. Add and read back one function.
4. Create the second module and derive cross-module calls.
5. Create the test module and derive its test relationship.
6. Return compact context and a stateless edit handle.
7. Dry-run the exact operator change with a minimal source and graph diff.
8. Qualify, apply, and prove graph/source round-trip agreement.
9. Automate the complete demonstration and comparative evidence hooks.

Do not stop after planning or after building only parser infrastructure. Reach
the end-to-end CLI demonstration in the scope. Make reasonable narrow
implementation decisions when the docs leave details open, record important
ones in the most specific existing document, and stop for direction only if a
choice would materially expand the product boundary.

Verification

Run the complete verification required by AGENTS.md and the development scope.
Keep noisy output in temporary logs. Report concise evidence for formatting,
warnings-as-errors compilation, tests, Credo, Dialyzer, Sobelow, the disposable
project demonstration, dry-run immutability, failed-qualification isolation,
managed-path write safety, stale-handle rejection, and reconstruction in a new
CLI process.

Final report

Lead with whether the MVP demonstration works. Then report:

- The public API and CLI commands implemented
- The managed Elixir subset supported
- The end-to-end demonstration evidence
- Verification commands and outcomes
- Any unsupported cases or honest remaining gaps
- The exact diff scope and working-tree status

Do not claim token savings until comparative measurements have actually been
collected.
```
