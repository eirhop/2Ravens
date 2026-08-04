# AGENTS.md

2Ravens is an experimental developer tool that helps humans and AI understand Elixir systems through code graphs, execution flows, process state, and runtime visualization.

Instead of navigating files, logs, and grep results, 2Ravens builds a semantic graph of your application so both humans and AI can quickly understand:

- What changed
- What behavior is affected
- How data flows through the system
- Which OTP processes participate
- What state changes
- Which tests cover the behavior
- What context an AI actually needs

## Vision

The long-term goal is to make understanding software dramatically easier in the AI era, where humans review and reason about systems that are increasingly written by AI.

## Repository rules

- 2Ravens is private pre-v1 software. Prefer a clean breaking change over deprecation; remove stale code and docs.

## Verification
Use credo, dialyxir and sobelow
```bash
mix format
mix compile --warnings-as-errors
mix test --no-compile 
```


## What the agent should optimize for

When making changes in this repo, optimize for:

1. Clear public API design
2. Small, composable modules
3. Documentation-first developer experience
4. Predictable runtime behavior
5. Elixir-native design over framework-heavy abstractions

## Elixir coding instructions

Follow Elixir best practices and idiomatic Elixir style:

- Prefer small, focused modules and functions
- Always alias nested modules
- Prefer pure functions and explicit data flow where possible
- Use pattern matching and multiple function heads to express intent clearly
- Use structs for domain data and behaviours for boundaries
- Keep return shapes consistent; avoid APIs whose options radically change return types
- Use pipelines only when they improve readability
- Avoid unnecessary comments; prefer clear names and good docs
- Write `@moduledoc`, `@doc`, types, and examples for all public API
- Add doctests or executable examples when practical
- Keep macros minimal and justified; prefer functions unless compile-time behavior is required
- Use OTP abstractions only when state, supervision, concurrency, or process boundaries are actually needed
- Raise only for truly exceptional situations; otherwise return explicit values
- Keep side effects at the edges of the system
- Make code easy to test with ExUnit through deterministic, isolated units

## Preferred change style

For new code:

- update or add typespecs for public functions
- write or improve moduledocs and docs
- add focused tests close to the changed behavior
- keep naming precise and boring
- avoid premature abstraction
- avoid introducing dependencies unless they clearly reduce complexity

## Priority order for decisions

When tradeoffs appear, prefer:

1. Correctness
2. Readability
3. Explicitness
4. Composability
5. Convenience

Choose the simpler design unless the more advanced design clearly solves a real problem already present in Favn.
