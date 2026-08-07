# Semantic editing

## Status

MVP contract. Ready for implementation.

Semantic editing is the first greenfield MVP foundation. It creates a narrow
repository graph while authoring ordinary Elixir, but it does not replace the
three later product phases, make the graph authoritative, or commit 2Ravens to
a persistent database.

## Purpose

File patches are a general interchange format, but they make an agent repeat
file paths, surrounding lines, and textual anchors. The MVP first lets an agent
create modules and functions as normal Elixir. Once 2Ravens has read that
source back and identified a precise program element, the agent can reuse its
identity for a smaller candidate change.

The product hypothesis is:

> Revision-bound semantic targets plus ordinary Elixir can reduce total agent
> tokens and incorrect-target edits while producing the same inspectable source
> diff.

The goal is not to make every edit semantic. The smallest representation that
remains clear should be selected for each change:

```text
New or substantially changed code -> ordinary Elixir
One known semantic property       -> compact semantic command
Several related edits             -> deferred until single edits are proven
Repository understanding          -> context query
```

## Authority and boundaries

Source and Git remain authoritative during this experiment:

```text
Source code = implementation authority
Git when present = named revision authority
Managed file hashes = current working revision
Repository graph = regenerable projection
Candidate = unapplied proposal derived from one base revision
```

2Ravens may construct a changed graph and source patch in memory, but accepting
a candidate writes ordinary Elixir into the working tree. Re-indexing that
source produces the next graph. A candidate never becomes an independent
second implementation.

Semantic editing is therefore not:

- A canonical source-code database
- A replacement for Elixir syntax
- A full IDE or autonomous coding agent
- Direct mutation of graph storage records
- Permission for an agent to assert compiler- or runtime-confirmed facts

## Workflow

```text
Large creation: init -> normal Elixir fragment ─┐
Small change:   context -> edit handle -> set ──┤
                                                 ↓
immutable candidate -> source materialization -> graph round-trip
-> compile and focused verification -> source and behavior diff
-> explicit apply -> working-tree source -> read-back graph
```

The agent does not submit callers, tests, effects, or other derivable
relationships. 2Ravens recalculates them and reports the resulting graph delta.

## Edit targets

The managed-source graph keeps canonical identities such as:

```text
module:RavensShop.Pricing
function:RavensShop.Pricing.discount/2
```

An edit-oriented context response may also provide compact aliases:

```text
r1:m1
r1:f2
r1:c4
r1:e7
```

The prefix binds the alias to repository revision `r1`. Internally, an edit
handle resolves to:

- The base revision or source hash
- The canonical graph identity
- A source range and structural fingerprint
- The node kind
- The properties the prototype permits an agent to change

Aliases are not durable graph identities. They are compact, stale-safe handles
for one revision. If source changes invalidate the handle, 2Ravens rejects the
operation and returns enough information to query the target again.

The initial CLI does not keep an alias table alive between commands. Each handle
must therefore be self-validating or deterministically resolvable from the
repository revision and indexed source.

## Change shapes

### Small semantic change

Change one permitted property of one known node:

```powershell
mix ravens set r1:e7.operator '>' --root tmp/ravens_shop
```

For the first MVP, `r1:e7` can identify the comparison operator in this
generated guard:

```elixir
def discount(subtotal, :vip) when subtotal >= 5_000, do: ...
```

The command produces a candidate equivalent to:

```diff
- def discount(subtotal, :vip) when subtotal >= 5_000, do: ...
+ def discount(subtotal, :vip) when subtotal > 5_000, do: ...
```

The agent edits an allowed semantic property. It does not edit a database row
or a compiler-confirmed relationship directly.

### Substantial addition

Normal Elixir remains the most compact and understandable input for a new
function. PowerShell sends the fragment through standard input so multiline
shell quoting does not become part of the change language:

```powershell
@'
def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
'@ | mix ravens create function RavensShop.Pricing `
  --root tmp/ravens_shop `
  --stdin
```

2Ravens parses the fragment, verifies that it contains definitions for one
function name and arity in the managed target module, derives the candidate
graph nodes, and chooses the source insertion point. The result includes the
generated source diff and new function identity.

### Replacement

A later operation may replace one complete function clause with ordinary
Elixir:

```powershell
@'
def discount(subtotal, :vip) when subtotal > 5_000,
  do: div(subtotal * 10, 100)
'@ | mix ravens replace r1:c4 --stdin
```

Clause replacement is safer than arbitrary inner-expression replacement when
source anchoring or comment preservation is uncertain. It is intentionally
deferred until `set` and creation prove the materialization boundary.

## Initial CLI contract

The Mix task is the first adapter because it is local, inspectable, easy to
benchmark, and does not add an MCP tool schema to every agent context.

### Query an editable target

```powershell
mix ravens context function:RavensShop.Pricing.discount/2 `
  --root tmp/ravens_shop `
  --for-edit
```

Expected compact result:

```text
revision r1
focus r1:f2 function:RavensShop.Pricing.discount/2
clause r1:c4
editable r1:e7.operator >=
caller r1:f4 function:RavensShop.Pricing.total/2
```

`--for-edit` is a CLI preset over the ordinary context-query contract. It does
not introduce separate graph semantics.

### Propose a small change

```powershell
mix ravens set r1:e7.operator '>' --root tmp/ravens_shop
```

Expected result:

```text
candidate c1
base r1
changed e7.operator >= -> >
impact f2 f4
parse pass
round_trip pass
compile pass
diff 1 line
```

### Propose an addition

```powershell
Get-Content -Raw .\total.ex | mix ravens create function `
  RavensShop.Pricing `
  --root tmp/ravens_shop `
  --stdin
```

Expected result:

```text
candidate c2
base r1
added function:RavensShop.Pricing.total/2
parse pass
round_trip pass
compile pass
```

### Apply after reviewing the dry run

```powershell
mix ravens set r1:e7.operator '>' `
  --root tmp/ravens_shop `
  --apply
```

The initial CLI does not persist `c1` between BEAM processes. Repeating the
operation with `--apply` rebuilds the candidate, verifies that the revision and
source hashes still match, writes the minimal working-tree patch, and re-indexes
the affected files in one invocation. It does not create a Git commit.

The first implementation does not include `remove`, `move`, `rename`, or batch
scripts. Each adds semantic and safety rules that should be justified by a
measured workflow.

## Candidate model

A candidate records:

```text
process-local candidate reference
base project revision, optional Git revision, and file hashes
ordered requested operations
resolved canonical targets
generated source patch
changed graph nodes and relationships
affected execution envelopes
validation checks and diagnostics
status: proposed | validated | applied | rejected
```

Requested facts and derived facts remain separate:

- The requested operation records what the agent asked to change.
- Source parsing derives syntax and structural relationships.
- Compiler evidence confirms resolvable relationships.
- Tests and runtime may provide observed evidence.
- Intent may be attached as provenance, but it never substitutes for evidence.

Candidates are immutable within one command. Correcting a failed or stale
candidate creates a new value rather than rewriting the old value. Durable
candidate storage is outside the initial spike.

## Validation pipeline

Every candidate must pass the checks appropriate to its qualification profile:

1. Resolve the revision-bound target.
2. Validate that the operation is permitted for the target kind.
3. Parse Elixir fragments without evaluating them.
4. Materialize the smallest source patch that preserves unrelated source.
5. Parse the changed source and rebuild its graph fragment.
6. Compare the rebuilt fragment with the proposed graph delta.
7. Format the affected source using Elixir's formatter rules.
8. Compile in an isolated candidate workspace.
9. Run focused tests when the affected graph identifies them.
10. Return source, graph, behavior, evidence, and uncertainty changes.

The candidate must be rejected when:

- Its base revision or source hash is stale.
- Its target is missing or ambiguous.
- The property is not editable for that node kind.
- The fragment is invalid Elixir.
- Source-to-graph round-trip differs from the proposed semantic change.
- Materialization changes unrelated nodes without disclosing them.

Compilation or test failures remain visible evidence. The product must never
label an uncompiled candidate as validated.

## MCP boundary

MCP remains a transport, not the change model. The CLI and any future MCP tool
must call the same ordinary Elixir API.

The initial MVP does not add an MCP write tool. After the CLI contract is
stable, a minimal MCP adapter may expose equivalent operations:

```text
set(at, to)
create_module(name, source)
create_function(module, source)
```

The model supplies only tool arguments. The MCP host supplies the JSON-RPC
envelope. Large Elixir bodies remain strings; the agent never serializes graph
records manually.

Example model arguments for the small edit:

```json
{"at":"r1:e7.operator","to":">"}
```

The MCP adapter is justified only if it improves compatibility or total task
cost over invoking the CLI through an existing shell tool.

## Token-efficiency evaluation

The relevant measurement is total cost for a correct completed change, not the
size of one command.

Compare the same frozen editing tasks under two conditions:

```text
Without Ravens
repository exploration + source reads + patch + corrections + verification

With Ravens
context query + semantic or Elixir input + corrections + verification
```

Record:

- Model input and output tokens when the host exposes them
- Context bytes as a tokenizer-independent fallback
- Tool calls and repository-exploration operations
- Time to the first correct candidate
- Incorrect-target and stale-target attempts
- Candidate correction rounds
- Generated source-diff size
- Compile and test outcome
- Human time and accuracy when explaining the behavior impact

Do not assume semantic editing is cheaper. A tiny direct file patch may beat a
context query plus semantic command when the target is already obvious. The
capability succeeds only when the complete workflow is materially better on
representative changes.

## First implementation slice

The first slice is the greenfield workflow defined in
[Development scope 01](scopes/01-greenfield-authoring-mvp.md). It starts with a
normal new Mix project and manages only files that 2Ravens creates.

### Prerequisites

- Safe project-root validation
- A small versioned manifest of managed paths
- Canonical module, function, clause, test, and expression identities
- Exact source ranges, structural fingerprints, and file-hash freshness
- Deterministic graph rebuilding from managed files
- Before-and-after source and graph comparison

### Milestone 1 — initialize and create a module

Initialize management metadata in a disposable Mix project. Create, format,
compile, and read back `RavensShop.Pricing`.

Proof:

- Initialization does not modify existing source.
- Only the expected managed path is written.
- A new CLI process reconstructs the same module identity from source.

### Milestone 2 — create functions

Accept complete definitions for one function name and arity through standard
input:

```powershell
Get-Content -Raw .\discount.ex | mix ravens create function `
  RavensShop.Pricing `
  --root tmp/ravens_shop `
  --stdin `
  --apply
```

Create `discount/2` and `total/2`, including the clauses, guards, comparison,
and local call required by the development scope. The fragments are ordinary
Elixir rather than a structured change language.

### Milestone 3 — connect modules and tests

Create `RavensShop.Checkout.checkout/2` and an ExUnit test module. Derive the
remote call path and static test relationship from read-back source. The agent
does not submit those relationships.

### Milestone 4 — context and edit handle

Return compact context for `RavensShop.Pricing.discount/2`, including its
clauses, callers, related test, source, freshness, and one revision-bound handle
for the first `>=` operator.

Proof:

- The handle resolves in a separate CLI process.
- It is rejected after a conflicting source change.
- Its response identifies the canonical target and allowed property.

### Milestone 5 — semantic `set`

Dry-run changing the first comparison from `>=` to `>`. Materialize a one-token
source change, reparse it, and prove graph round-trip equality without changing
the real project.

Then repeat the operation with `--apply`. Qualify it in an isolated project,
verify base hashes immediately before writing, read the accepted source back,
and prove that the reconstructed graph equals the qualified graph.

### Milestone 6 — comparative benchmark

Run the same two-module creation and small edit with and without 2Ravens under
the same model, reasoning effort, permissions, and completion rule. Decide
whether to broaden the managed Elixir subset before adding brownfield import,
MCP writes, persistence, batch scripts, or more edit operations.

## Exit gate

The semantic-authoring MVP is technically complete only when:

- No accepted candidate silently changes unrelated source or graph facts.
- Stale and ambiguous targets fail safely.
- Source-to-graph round trips are deterministic for the supported edits.
- Generated source remains ordinary, reviewable Elixir.
- The complete workflow preserves or improves correctness.
- The graph and source diff explain the behavior impact more clearly than the
  source diff alone.
- The comparative workflow records tokens or bytes, operations, corrections,
  correctness, and review evidence without inventing a favorable result.

More write operations should be added only when at least one representative
workflow materially improves total context, operations, correctness, or review
understanding. If the technical conditions fail, 2Ravens should not broaden its
write surface; the graph may still provide value for context and review.
