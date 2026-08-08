# Semantic-memory lifecycle benchmark

This frozen benchmark compares `files_only`, `source_indexed`, and
`semantic_memory` across six sequential tasks. All projects contain
behaviorally and byte-equivalent managed source before the task sequence. The
acceptance oracle remains in this directory, outside every analyzed project.

Run from the repository root:

```powershell
mix run benchmarks/semantic_memory/run.exs
```

The recorder derives request/result/context bytes and operation counts from
events. It measures creation overhead separately, moves and renames the same
function before task five, and reports cumulative checkpoints after tasks 1,
3, 5, and 6. Model tokens stay `unavailable` because this automated run does
not expose host model accounting. Wall time is diagnostic only.

The deterministic correctness proxy does not pretend to be an agent run:
files-only facts come from ordinary reads, source-indexed facts come from the
Scope 01 graph, and semantic-memory facts come from persisted context. A future
comparative agent run must retain the frozen prompts, controls, oracle, and
completion rule.
