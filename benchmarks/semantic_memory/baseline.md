# Semantic-memory lifecycle baseline

One local Windows run of
`mix run benchmarks/semantic_memory/run.exs` completed the frozen six-task
lifecycle with byte-equivalent initial source. Model-token values were not
exposed and remain `unavailable`. Timings are machine-specific diagnostics.

## Creation overhead

| Metric | Files only | Source indexed | Semantic memory |
| --- | ---: | ---: | ---: |
| Tool-request bytes | 990 | 1,102 | 583 |
| Tool-result bytes | 199 | 352 | 1,845 |
| Creation context bytes | 1,189 | 1,454 | 2,428 |
| Qualification output bytes hidden behind receipts | 0 | 0 | 3,944 |
| Qualification subprocesses | 2 | 2 | 12 |
| Diagnostic wall time | 889 ms | 869 ms | 6,311 ms |

Semantic memory starts with the largest visible context and substantially more
qualification work. Compact receipts prevent the 3,944 qualification bytes
from becoming author-facing context, but they do not make that work disappear.

## Sequential task results

Tool-result bytes are derived from recorded outputs. Correctness is checked
against the external oracle; `pass` means every required fact and no forbidden
claim was returned.

| Task | Files only | Source indexed | Semantic memory |
| --- | ---: | ---: | ---: |
| Explain intent | 393 / fail | 41 / fail | 304 / pass |
| Identify callers | 572 / pass | 88 / pass | 301 / pass |
| Separate requested, derived, and observed test meaning | 825 / fail | 94 / fail | 481 / pass |
| Report change impact | 825 / pass | 124 / pass | 418 / pass |
| Continue after move and rename | 837 / fail | 147 / fail | 617 / pass |
| Review renamed behavior | 837 / fail | 147 / fail | 614 / pass |

Semantic memory completed 6/6 tasks. Files-only and source-indexed each
completed 2/6. The difference is requested intent, intended-test meaning, and
stable identity through the simulated move and rename. No condition claimed
per-function observed coverage from a passing test suite.

## Cumulative context

Creation overhead is included before task one.

| Checkpoint | Files only | Source indexed | Semantic memory |
| --- | ---: | ---: | ---: |
| Task 1 | 1,626 | 1,539 | 2,776 |
| Task 3 | 3,160 | 1,858 | 3,695 |
| Task 5 | 4,956 | 2,263 | 4,864 |
| Task 6 | 5,871 | 2,488 | 5,556 |

Semantic memory reaches cumulative context break-even against repeated file
reads at task 5 and finishes 315 bytes lower. It never reaches break-even
against the compact source-indexed condition; final cumulative context is
5,556 bytes versus 2,488 bytes.

## Warm query and cold reconstruction

| Probe | Tool-result bytes | Diagnostic wall time | Graph rebuilt | Intent |
| --- | ---: | ---: | --- | --- |
| Warm semantic query | 614 | 20 ms | no | available |
| Missing-store reconstruction | 578 | 53 ms | yes | unavailable |

Cold reconstruction recovered zero requested intents, as required. Its smaller
output is caused by missing knowledge and is not an efficiency win.

## Decision

The differentiated capability works: semantic memory preserves useful
requested facts, keeps provenance distinct, retains identity across the frozen
movement/rename simulation, and improves correctness. The expansion gate still
fails because cumulative context does not break even against source indexing
within the frozen sequence. Persistence should remain bounded and optional
while context packing is improved or a longer frozen lifecycle demonstrates
amortization. Wall time is not used as the product gate.
