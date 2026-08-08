# Authoring-time semantic memory

## Status

Implemented experiment; product gate failed against source indexing.

The first greenfield authoring slice proved that 2Ravens can safely create,
query, and semantically edit ordinary Elixir. Its mechanics benchmark did not
show an efficiency advantage: 2Ravens used slightly more authoring input,
substantially more author-facing output, and more qualification work. Model
token counts were unavailable. See the recorded
[greenfield baseline](../benchmarks/greenfield_authoring/baseline.md).

That benchmark remains valid for the workflow it measured. Scope 02 later
proved that the persisted model can preserve requested facts and improve task
correctness, but its frozen lifecycle did not beat source indexing on cumulative
context. The store therefore remains bounded infrastructure, while the next
experiment reduces authoring round trips through the
[entity authoring API](ENTITY_AUTHORING.md).

## Revised product hypothesis

> Authoring-time semantic memory can preserve knowledge that source indexing
> cannot recover and can amortize its initial token overhead across later
> understanding, change, and review tasks.

The relevant comparison is cumulative context across a software lifecycle, not
whether one initial file write is faster than one semantic operation.

The hypothesis succeeds only if stored semantic memory:

- Preserves useful information unavailable to a source-only indexer.
- Lets later context queries return less model input than repeated file reads.
- Maintains equal or better task correctness.
- Keeps requested claims, derived facts, and observed evidence distinct.
- Detects source/database drift and fails safely.

## What persistence can add

Source indexing can derive modules, functions, clauses, guards, calls, source
locations, and some test relationships. It cannot reliably reconstruct:

- Why a function or change exists.
- The behavior the author intended to preserve.
- Which test was intended to prove which behavior.
- The reasoning behind a relationship or boundary.
- Stable identity through later movement or rename.
- Earlier uncertainty and the evidence that resolved it.

2Ravens should capture this information when the agent already knows it, using
small optional fields alongside normal Elixir. It should not ask the agent to
serialize graph records.

## Three fact classes

Every persisted fact belongs to one class.

### Requested knowledge

Supplied by an AI or human as a claim or intention:

- Function or change intent
- Intended behavior
- Intended test target
- Change reason
- Requested architectural relationship

Requested knowledge is useful but not compiler truth. It always records its
authoring operation, revision, and origin.

### Derived knowledge

Reconstructed deterministically from managed source or compiler evidence:

- Definitions and containment
- Clauses, patterns, guards, and comparisons
- Calls and static test references
- Source projections and structural fingerprints
- Compiler-confirmed relationships

The agent never submits these facts as authoritative edges.

### Observed evidence

Produced by an executed check or runtime observation:

- Formatting, compilation, and test outcomes
- Test execution
- Runtime coverage
- Process and message observations

A passing test suite is evidence about one revision. It is not proof that a
particular function was executed unless capture demonstrates that relationship.

## Relationship example

A test relationship must not collapse several meanings into one edge:

```text
PricingTest --intended_to_test--> Pricing.total/2
  origin: requested

PricingTest --statically_calls--> Checkout.checkout/2
  origin: source parser

test run --passed_at_revision--> revision r4
  origin: test execution

PricingTest --observed_cover--> Pricing.total/2
  status: unknown until runtime capture proves it
```

Queries may group these facts for presentation, but they retain separate
provenance and confidence.

## Authority model

The next MVP introduces a local embedded semantic store without making it the
only copy of the program:

```text
Embedded database = operational semantic memory
Source code = compiler input and recoverable implementation
Git = named history and collaboration when present
Compiler and tests = behavioral evidence
```

The database may contain information that source cannot reconstruct. During the
experiment it is local machine state beneath `.ravens/` and is not committed to
Git. If it is missing, 2Ravens rebuilds derived facts from managed source and
reports requested intent as unavailable rather than inventing it.

Portable export, branch merge, and collaborative synchronization are deferred
until semantic memory demonstrates product value.

## Authoring input

Large changes remain normal Elixir with concise semantic metadata:

```powershell
@'
def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
'@ | mix ravens create function RavensShop.Pricing `
  --intent "Calculate final price after the tier discount" `
  --stdin `
  --apply
```

A test may explicitly record intended coverage without pretending it has been
observed:

```powershell
Get-Content -Raw .\pricing_test_body.exs | `
  mix ravens create module RavensShop.PricingTest `
  --test `
  --for function:RavensShop.Pricing.total/2 `
  --intent "Protect VIP checkout pricing" `
  --stdin `
  --apply
```

The system derives calls and source relationships, assigns stable entity IDs,
qualifies the source projection, and persists accepted semantic facts.

## Compact context

Tool output becomes input to the model on a later turn. Compact output is
therefore a core product boundary, not cosmetic formatting.

The default successful mutation response should be a receipt:

```text
ok operation:o17 revision:r4
added function:RavensShop.Pricing.total/2 entity:n8
derived calls:1 requested_intents:1
checks parse,round_trip,compile,test pass
```

Full source, diff, provenance, and diagnostics are returned through explicit
detail options or on failure. Context queries return the smallest facts and
paths needed for the request and disclose omitted detail and frontier.

## Lifecycle benchmark

The semantic-memory hypothesis requires three isolated conditions:

1. **Files only:** normal search, file reads, and file edits.
2. **Source-indexed:** the current source-derived graph without authoring-time
   intent.
3. **Semantic memory:** the same derived graph plus persisted stable identities,
   requested intent, typed relations, and evidence.

All conditions start with behaviorally equivalent source. Then they execute the
same frozen sequence of later tasks, for example:

- Explain why a shared calculation exists.
- Change a boundary and identify every affected caller.
- Identify intended test protection separately from observed evidence.
- Continue work after moving or renaming a semantic entity.
- Review a multi-module behavior change.

Record after tasks 1, 3, 5, and the final task:

- Model input and output tokens when available
- Tool-request and tool-result UTF-8 bytes
- Cumulative context bytes
- Repository searches, file listings, and source reads
- Semantic-memory queries and facts reused
- Incorrect assumptions and missed relationships
- Correction rounds
- Task correctness against an external oracle
- Wall-clock time as a diagnostic, not a product gate

The benchmark must use the same model, reasoning effort, permissions, prompts,
and completion rule for every condition. Unavailable values remain unavailable.

## Decision gate

Continue expanding semantic persistence only when the frozen lifecycle
comparison shows that it:

- Preserves useful requested knowledge that indexing lacks.
- Reaches cumulative context break-even within the frozen task sequence.
- Uses less cumulative model input after break-even.
- Preserves or improves correctness.
- Keeps freshness, provenance, uncertainty, and missing evidence visible.

If the database only stores the AST and relationships that source indexing
already derives, it is a cache rather than a differentiated product capability.
The project should then keep persistence optional and return focus to context
and review.

## Non-goals for this experiment

- Making SQLite the canonical source-code store
- Committing an opaque database to Git
- Database synchronization across branches or machines
- Brownfield intent reconstruction
- A graph database or general SQL/Cypher interface
- A custom programming or metadata language
- MCP writes, UI, runtime tracing, or additional edit verbs
- Optimizing wall-clock performance before context value is measured
