# Ravens benchmark app

This small consumer application is the first dogfooding target for 2Ravens. It
uses the repository root as a development-only path dependency, so the newest
local 2Ravens code is available without publishing a package.

Run the application tests:

```text
cd dev/benchmark_app
mix deps.get
mix test
```

Once the Mix task exists, run 2Ravens from this directory:

```text
mix ravens
```

## What the benchmark contains

- Two entry points with shared pricing dependencies
- Multiple function clauses and guards
- Caller-to-callee argument and result mappings
- Success and failure branches expressed through `with` and `if`
- A `GenServer.call/2` message connected to `handle_call/3`
- Observable process-state changes
- A configured behaviour implementation representing an external boundary
- Tests that enter through both public functions and the OTP boundary

## Benchmark contract

The acceptance oracle lives outside this analyzed application so its terms do
not pollute source, documentation, or keyword results:

- [`expected.exs`](../../benchmarks/ravens_benchmark/expected.exs) defines
  exact queries and required semantic facts.
- [`baseline.md`](../../benchmarks/ravens_benchmark/baseline.md) defines the
  blinded without-Ravens measurement procedure.
- [`tasks.exs`](../../benchmarks/ravens_benchmark/tasks.exs) contains the
  frozen task prompts.

The first implementation milestone passes when 2Ravens reproduces these facts
locally and deterministically, discloses unresolved relationships, and merges
the shared pricing context in the multi-focus query.
