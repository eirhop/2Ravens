# Greenfield authoring comparison baseline

The frozen comparison task is defined in `task.exs`. No model-token comparison
has been collected, so tokens remain `unavailable` and no token-saving claim is
made.

## Automated mechanics snapshot

One local Windows run of `mix run benchmarks/greenfield_authoring/run.exs`
produced the following schema-v2 evidence. Timings are machine-specific and are
not a product improvement target. Counts and bytes now come from recorded
events; the bootstrap Mix project is created before both timers start.

| Metric | Ordinary files | 2Ravens |
| --- | ---: | ---: |
| Input bytes | 1,098 | 1,363 |
| Author-facing output bytes | 432 | 6,442 |
| Qualification output bytes | 432 | 5,262 |
| Workflow tool calls | 10 | 10 |
| Internal qualification commands | 6 | 16 |
| Correction rounds | 0 | 0 |
| Final diff lines | 1 | 1 |
| Time to first correct result | 2,692 ms | 8,166 ms |
| Incorrect-target attempts | 0 | 0 |
| Compile | pass | pass |
| Tests | pass | pass |

The final ordinary source files were byte-for-byte equal. The 2Ravens dry run
left source unchanged, and its accepted graph reconstructed equally from the
resulting files.

In simple terms: this run is technically correct, but 2Ravens is still about
3.0 times slower, returns substantially more author-facing text, and performs
about 2.7 times as many qualification subprocesses. The extra work is mainly
the MVP safety rule that every applied creation and edit, plus the semantic
edit dry-run, is formatted, compiled, and tested in a fresh project copy. This
is not evidence that the 2Ravens workflow is more efficient.

The earlier schema-v1 numbers used hardcoded counters, unequal input/output
definitions, and different timing endpoints. They are superseded rather than
treated as a performance improvement baseline.

The automated MVP test records correctness evidence for the 2Ravens condition:
ordinary formatted source, isolated compilation and tests, one changed source
line, dry-run immutability, stale-handle rejection, managed-path confinement,
and graph reconstruction in another CLI process.

A comparative agent run must still use the same model, reasoning effort,
permissions, and completion rule for both conditions. It must record every
field listed in `task.exs`; unavailable host token counts stay explicitly
unavailable.
