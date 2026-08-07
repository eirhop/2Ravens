# Development scope 01 — Greenfield semantic authoring MVP

## Status

Ready for implementation.

This is the first substantial development scope for 2Ravens. It proves that an
AI can create and then safely change a small ordinary Elixir system through
2Ravens without requiring a database, daemon, MCP server, or general-purpose
brownfield indexer.

## Decision

The MVP is greenfield-first and write-focused, but narrowly two-way:

```text
normal Elixir input
-> semantic model
-> ordinary source files
-> formatter, compiler, and tests
-> read back only 2Ravens-managed files
-> verified semantic model
```

2Ravens creates and edits a constrained subset of Elixir. It immediately reads
its generated files back to prove that the graph matches the source the Elixir
toolchain sees.

General importing of arbitrary existing Elixir repositories is a later Phase 1
capability. Read-back verification of files created by 2Ravens is part of this
MVP and must not be postponed.

## Outcome

A developer can start from a new Mix project and use `mix ravens` to:

1. Mark the project as managed by 2Ravens.
2. Create two modules.
3. Add several ordinary Elixir function definitions that call one another.
4. Create one ExUnit test module.
5. Query the resulting functions and relationships.
6. Change one known comparison operator through a revision-bound handle.
7. Review an ordinary source diff and graph impact.
8. Format, compile, and test the candidate in isolation.
9. Apply explicitly and rebuild the graph from the resulting source.

This is a product proof, not merely a parser demonstration. The flow must be
usable through a thin CLI and ordinary Elixir APIs from beginning to end.

## Required demonstration

The exact temporary path may differ, but the completed workflow must support
the following logical sequence on Windows PowerShell.

Create a normal Mix project, then initialize 2Ravens metadata:

```powershell
mix new tmp/ravens_shop
mix ravens init --root tmp/ravens_shop
```

`init` validates the target and creates only a small versioned management
manifest. It does not replace `mix new`, rewrite existing source, or create a
graph database.

Create the first module:

```powershell
mix ravens create module RavensShop.Pricing `
  --root tmp/ravens_shop `
  --apply
```

Add the clauses of one function using normal Elixir through standard input:

```powershell
@'
def discount(subtotal, :vip) when subtotal >= 5_000,
  do: div(subtotal * 10, 100)

def discount(subtotal, :vip) when subtotal >= 0,
  do: div(subtotal * 5, 100)

def discount(subtotal, :standard) when subtotal >= 0,
  do: 0
'@ | mix ravens create function RavensShop.Pricing `
  --root tmp/ravens_shop `
  --stdin `
  --apply
```

Add another function to the same module:

```powershell
@'
def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
'@ | mix ravens create function RavensShop.Pricing `
  --root tmp/ravens_shop `
  --stdin `
  --apply
```

Create a second module and a cross-module call:

```powershell
mix ravens create module RavensShop.Checkout `
  --root tmp/ravens_shop `
  --apply

@'
def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)
'@ | mix ravens create function RavensShop.Checkout `
  --root tmp/ravens_shop `
  --stdin `
  --apply
```

Create a test module. The standard-input fragment is ordinary code inside the
generated `defmodule`; it is not a new data or programming language.

```powershell
@'
use ExUnit.Case, async: true

test "prices a VIP checkout" do
  assert RavensShop.Checkout.checkout(6_000, :vip) == 5_400
end
'@ | mix ravens create module RavensShop.PricingTest `
  --root tmp/ravens_shop `
  --test `
  --stdin `
  --apply
```

Query the created behavior:

```powershell
mix ravens context function:RavensShop.Pricing.discount/2 `
  --root tmp/ravens_shop `
  --for-edit
```

The response identifies the clauses, guards, direct callers, test relationship,
source references, current revision, and one editable operator handle.

Dry-run changing the first threshold from inclusive to exclusive:

```powershell
mix ravens set <revision-bound-handle>.operator '>' `
  --root tmp/ravens_shop
```

Expected result:

```text
changed operator >= -> >
source diff 1 line
direct impact RavensShop.Pricing.discount/2
upstream impact RavensShop.Pricing.total/2 RavensShop.Checkout.checkout/2
related test RavensShop.PricingTest
parse pass
round_trip pass
compile pass
tests pass
working_tree unchanged
```

The result must also disclose the supported guard-level boundary change and
that the exact `5_000` input is not exercised by the created test:

```text
at 5_000 before: first VIP clause can match (subtotal >= 5_000)
at 5_000 after:  first VIP clause cannot match; second VIP clause can match
boundary test evidence: absent
```

Apply only after reviewing the dry run:

```powershell
mix ravens set <revision-bound-handle>.operator '>' `
  --root tmp/ravens_shop `
  --apply
```

The command re-resolves and qualifies the operation in the current process. It
must reject the edit if the source changed after the handle was produced.

## Fast-progress rule

Keep one runnable path at every checkpoint:

1. Initialize a temporary Mix project and create one empty module.
2. Add one function and read it back into a deterministic graph.
3. Add the cross-module call and expose it through `context`.
4. Add the test relationship.
5. Dry-run the one-token edit.
6. Qualify and explicitly apply it.

Do not spend the opening work on general graph abstractions. The first visible
result should be a correctly generated, formatted, and compiled module.

## Product constraints

- Everything runs locally and offline.
- Generated source is ordinary Elixir and works without 2Ravens at runtime.
- Source and Git remain recoverable authorities.
- The compiler and tests remain the behavioral judges.
- The graph is rebuilt from current managed source on every MVP CLI command.
- Only paths recorded as 2Ravens-managed may be changed.
- Relationships are derived from source; the agent does not submit call or test
  edges.
- Dry-run is the default for authoring commands; `--apply` is explicit.
- Public APIs have moduledocs, docs, typespecs, and focused examples.
- Errors use consistent explicit return values.
- Unsupported syntax and uncertainty are reported, never guessed away.

## Supported source subset

Support only what the demonstration needs:

- One ordinary `defmodule` per managed file
- `alias`, `import`, and `use ExUnit.Case` declarations
- Public `def` functions with one or several clauses
- Positional arguments and literal or variable patterns
- Standard guard comparisons
- Local and explicit remote calls
- Basic arithmetic and `div/2`
- ExUnit `test` blocks and direct calls from their bodies
- Exact source references for modules, functions, clauses, calls, tests, and
  editable comparisons

The parser may observe other valid syntax, but it must not claim complete
semantics for it. A write touching an unsupported managed structure fails with
a structured diagnostic. Unrelated unsupported source remains unchanged.

## Deliverables

### 1. Safe project root and management manifest

Implement `mix ravens init --root PATH` over an ordinary Elixir API.

Initialization must:

- Resolve and validate an absolute project root.
- Require an existing Mix project.
- Refuse broad or unsafe paths.
- Create a small versioned manifest beneath `.ravens/`.
- Record only management metadata such as schema version and managed paths.
- Avoid storing source bodies, ASTs, graph facts, or compiler claims.

The manifest format is internal and replaceable. Source files remain sufficient
to compile and understand the generated application without the manifest.

Acceptance:

- Initializing twice is deterministic and does not duplicate data.
- Initialization never modifies existing `.ex` or `.exs` files.
- A path outside the validated project cannot become a write target.
- A missing, corrupt, or unsupported manifest fails explicitly.

### 2. Repository revision and source identities

Introduce small immutable types for:

- Project root
- Managed relative path
- Current Git revision when present
- Working-tree and managed-file content hashes
- Source ranges with line and column positions
- Canonical semantic identities
- Evidence origin and freshness

Acceptance:

- Identical managed source produces identical identities and hashes.
- Paths are repository-relative and deterministic across machines.
- A changed file invalidates handles created from its prior content.
- The implementation works when the temporary project is not a Git repository.

### 3. Module creation

Implement `create module` as a dry-run candidate with optional `--apply`.

It must:

- Validate an Elixir module name without creating atoms from unbounded input.
- Infer the conventional `lib/.../*.ex` path for normal modules.
- Infer `test/.../*_test.exs` only when `--test` is explicit.
- Accept an optional ordinary Elixir module-body fragment through standard
  input.
- Reject path, module, and source collisions.
- Generate a minimal documented `defmodule` and format it.
- Record the new path as managed only after a successful apply.

The domain API receives strings and structured values. Business behavior must
not live in the Mix task.

### 4. Function creation

Implement `create function MODULE --stdin`.

The fragment may contain multiple clauses, but all top-level definitions must
belong to one function name and arity. Reject nested modules, unrelated
definitions, arbitrary top-level expressions, and source that does not parse.

Insert the definitions before the target module's final `end`, preserve all
unrelated bytes until formatting, and return:

- Added canonical function and clause identities
- Derived calls and comparison expressions
- Exact ordinary source diff
- Qualification evidence
- Known unsupported facts

An `--apply` invocation qualifies in an isolated copy before checking the base
hash and writing the managed source.

### 5. Narrow read-back indexer

After every successful authoring operation, parse every path listed in the
management manifest and rebuild the graph in memory.

The MVP indexer is deliberately not a repository importer. It must:

- Read only managed paths.
- Derive modules, functions, clauses, guards, comparisons, calls, and tests for
  the supported subset.
- Preserve exact source ranges and evidence.
- Mark unsupported constructs explicitly.
- Never evaluate managed application source.
- Produce deterministic per-file fragments.

Acceptance:

- The graph reconstructed in a new BEAM process equals the accepted graph.
- Re-reading unchanged source is deterministic.
- Missing or externally changed managed files are visible in freshness data.
- The tool never silently expands its write authority to unlisted files.

### 6. Minimal graph kernel and context query

Use immutable structs and maps. Support only:

- Nodes with canonical identity, kind, source, revision, and evidence
- Ordered clauses and containment
- `defines`, `calls`, and `tested_by` relationships
- Lookup by canonical function identity
- Direct and transitive upstream calls for impact
- Per-file fragment replacement
- Compact function-focused `context` output

The context API must return selected source, callers, callees, related tests,
editable comparisons, freshness, unsupported facts, and traversal frontier.
Unsupported focus and traversal forms return explicit errors rather than
pretending the complete Phase 1 query contract exists.

### 7. Stateless revision-bound edit handle

The editable comparison handle must survive separate CLI processes without a
daemon or persistent alias table. It binds:

- Version
- Managed file hash
- Canonical containing function and clause fingerprint
- Target expression fingerprint
- Editable property

The exact encoding is an implementation detail. It must be compact, opaque,
self-validating or deterministically resolvable, and safe as one CLI argument.

Acceptance:

- A handle returned by `context` resolves in a later CLI invocation.
- Unrelated line movement may be tolerated when the structure still resolves
  uniquely.
- A changed target fails stale instead of selecting a nearby token.
- Ambiguity or collision fails explicitly.

### 8. Semantic `set`

Implement only comparison-operator replacement for a known supported node.

`set` must:

- Permit a bounded allowlist of comparison operators.
- Replace only the exact operator token.
- Default to a dry run.
- Return source and graph deltas plus affected callers and tests.
- Reparse the changed source and compare rebuilt facts with the proposed graph.
- Reject unrelated source or graph changes.

Do not expose arbitrary graph-property mutation. The operation changes source;
derived relationships are recalculated.

### 9. Isolated qualification and explicit apply

Qualify every applied creation or edit in a verified temporary project copy:

1. Materialize the candidate.
2. Format the affected files.
3. Rebuild the graph from the candidate source.
4. Compare expected and rebuilt facts.
5. Compile with warnings as errors.
6. Run the project tests.
7. Check base hashes immediately before the real write.
8. Write only managed candidate paths.
9. Re-index the accepted source and report final evidence.

The real target must remain unchanged on parse, graph, formatting, compilation,
or test failure. Apply never stages or commits Git changes.

### 10. End-to-end acceptance and comparison

Automate the required demonstration using disposable project roots. Add a
frozen task that compares:

```text
ordinary file creation and patching
versus
2Ravens creation, context, and semantic set
```

Record total tokens when available, input/output bytes, tool calls, correction
rounds, diff size, time to first correct result, compile/test outcomes, and
incorrect-target attempts. Do not invent improvement targets before collecting
the baseline.

The MVP may pass technically even if the first token comparison is neutral. It
must not pass if the 2Ravens path is less correct or hides relevant changes.

## Suggested code boundaries

These are responsibility hints, not required application boundaries:

```text
TwoRavens.Project          root validation and managed paths
TwoRavens.Manifest         small versioned management metadata
TwoRavens.Repository       revisions, hashes, and source identities
TwoRavens.Source           parsing and deterministic file fragments
TwoRavens.Graph            nodes, edges, lookup, and traversal
TwoRavens.Authoring        candidate orchestration
TwoRavens.CreateModule     module candidate construction
TwoRavens.CreateFunction   function candidate construction
TwoRavens.EditHandle       stateless handle encoding and resolution
TwoRavens.Set              bounded semantic property change
TwoRavens.Materializer     minimal safe source changes
TwoRavens.Qualifier        isolated format, compile, and test evidence
TwoRavens.Context          focused query and response contract
Mix.Tasks.Ravens           thin CLI adapter
```

Prefer small structs and pure functions. Keep side effects at project discovery,
file materialization, and qualification boundaries. Public APIs use consistent
return shapes:

```elixir
{:ok, value}
{:error, reason}
```

Add structured errors only where callers need recovery information, such as
unsafe roots, unmanaged paths, collisions, invalid fragments, stale handles,
ambiguous targets, or qualification failures.

## Checkpoints

Each checkpoint must leave a runnable, tested path:

1. **Initialize:** safely mark a disposable Mix project as managed.
2. **Create module:** generate, format, compile, read back, and report one module.
3. **Create function:** add one function and reconstruct its graph in a new
   process.
4. **Connect:** add the second module and expose local and remote call edges.
5. **Test:** create the test module and derive its relationship.
6. **Inspect:** return compact function context and an editable handle.
7. **Edit:** dry-run the one-token operator change with exact impact.
8. **Apply:** qualify, write, and prove accepted graph/source agreement.
9. **Compare:** collect ordinary-file and 2Ravens workflow evidence.

Do not postpone all runnable behavior until every graph abstraction exists.

## Out of scope

- Importing or writing arbitrary existing brownfield source
- Indexing files not listed as managed
- Persistent graph or candidate database
- ETS, a daemon, supervision, or file watching
- MCP write tools or MCP context transport
- UI or graph visualization
- Custom programming or data input languages
- Arbitrary AST, token, or graph-property edits
- `replace`, `remove`, `move`, `rename`, or batch operations
- General macro expansion, protocols, behaviours, or OTP relationships
- Full dataflow or abstract execution
- Tolerant parsing of invalid intermediate files
- Complete Phase 1 context-query support
- Automatic Git staging, commits, branches, or pull requests
- New production dependencies without demonstrated need

## Test strategy

Add focused tests close to each behavior:

- Pure unit tests for paths, manifests, hashes, identities, and handles
- Parser fixtures for the supported managed-source subset
- Module and function candidate tests for valid input and collisions
- Graph tests for definitions, calls, tests, and upstream impact
- Round-trip tests proving deterministic reconstruction
- Stale, ambiguous, unsafe-root, and unmanaged-path rejection tests
- Qualification failure tests proving the real target remains unchanged
- CLI integration tests using disposable Mix projects
- One complete demonstration test

Never run destructive apply tests against checked-in source fixtures.

## Required verification

Keep noisy output in temporary logs and report one concise line per successful
command:

```powershell
mix format
mix compile --warnings-as-errors
$env:MIX_ENV = 'test'
mix compile --warnings-as-errors
mix test --no-compile
Remove-Item Env:MIX_ENV
mix credo --strict
mix dialyzer
mix sobelow
```

Also verify:

- The required demonstration passes from a clean disposable Mix project.
- Dry-run commands do not modify managed source.
- Failed qualification leaves the real project byte-for-byte unchanged.
- Apply changes only the intended managed paths.
- A new CLI process reconstructs the same accepted graph.
- Documentation links and examples remain current.

## Completion gate

This scope is complete only when:

- The required CLI flow works through ordinary testable Elixir APIs.
- Every created file is normal formatted Elixir.
- Relationships are derived rather than asserted by the caller.
- Read-back reconstruction equals the accepted semantic model.
- Stale handles and unmanaged writes fail safely.
- Source changes are dry-run by default and explicit on apply.
- Qualification is isolated and reports honest compiler and test evidence.
- The one-token edit preserves all unrelated source.
- The demonstration and comparison are reproducible.
- No database, daemon, MCP write tool, UI, or brownfield importer was added.

If the slice requires broad infrastructure or a custom language to work, stop
at the failing checkpoint and revise the architecture from evidence.
