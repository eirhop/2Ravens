# Entity-authoring lifecycle — Luna high

Date: 2026-08-08

## Result

The final three-job lifecycle favors 2Ravens on every measured efficiency
dimension. This is promising product evidence, not a general performance
theorem.

Three cumulative jobs used fresh `gpt-5.6-luna` high-reasoning tasks in two
isolated Git worktrees created from commit `3693b3b`. Both conditions started
with the same Epic 1+2 source and eight passing tests. Each condition carried
its own Epic 3 output into Epic 4, then its own Epic 4 output into Epic 5.

The Ravens condition used the project-bound MCP server for application source
and tests. The files condition had the 2Ravens dependency and two tracked
`.ravens` control files removed and used ordinary targeted file tools. Every
job used a new task with no prior job context.

| Job | 2Ravens total tokens | Files total tokens | Ravens delta | 2Ravens wrappers | Files wrappers | Ravens wall | Files wall |
|---|---:|---:|---:|---:|---:|---:|---:|
| Epic 3 | 209,972 | 593,829 | -64.6% | 5 | 14 | 120.4 s | 257.3 s |
| Epic 4 | 397,005 | 631,557 | -37.1% | 11 | 17 | 169.4 s | 248.7 s |
| Epic 5 | 264,975 | 464,610 | -43.0% | 8 | 13 | 130.0 s | 175.4 s |
| **Total** | **871,952** | **1,689,996** | **-48.4%** | **24** | **44** | **419.8 s** | **681.4 s** |

Cumulatively, 2Ravens used:

- 48.6% fewer input tokens
- 17.9% fewer uncached input tokens
- 37.1% fewer output tokens
- 37.7% fewer reasoning-output tokens
- 45.5% fewer model-visible tool wrappers
- 35.1% fewer underlying tool invocations (37 versus 57)
- 38.4% less wall time

Both final repositories independently passed warnings-as-errors test
compilation and their complete test suites. The Ravens repository finished with
42 passing tests; the files repository finished with 31. A source-level audit
confirmed that both suites cover the required Epic 3–5 boundaries and
acceptance examples. The test-count difference means the implementations are
not byte-identical and is one reason to avoid treating this probe as a theorem.

## What the 2Ravens agents did

The MCP metric sink recorded 15 calls:

- 10 discovery calls
- one batched context call
- four successful bundle-creation calls
- four qualifications
- zero repair calls
- zero repeated submitted-source bytes

Epic 3 used one discovery call and one complete bundle. Epic 4 used seven
discovery calls, one batched context call, then two bundles because the agent
forgot the test module in its first otherwise-valid submission. Epic 5 used two
discovery calls and one complete bundle.

Two protocol improvements were exercised directly:

- Epic 4 requested unsupported module proof fields. 2Ravens kept the supported
  fields, returned correction warnings, and applied the valid bundle instead of
  rejecting it.
- Epic 4 requested a discovery limit of 50. 2Ravens clamped it to 20 with a
  warning instead of requiring another call.

Every accepted receipt reported formatting, warnings-as-errors compilation,
tests, source read-back, graph comparison, semantic persistence, and
`verification_complete: true`. The agents performed no post-apply context or
shell-test verification.

## Before and after

The earlier lifecycle with the same model class favored ordinary files:
2Ravens used 54.1% more total tokens, 20.5% more wrappers, and 51.3% more wall
time. Its expensive paths came from guessed tool shapes, discarded malformed
large requests, invalid selectors, namespace guesses, and awkward test repair.

The final run reverses that result after adding:

- flat dedicated MCP tools
- canonical discovery with paths, docs, and public-function summaries
- batched exact context and same-call return proof
- retained malformed-request patching without source resend
- first-class test entities and safe draft tombstones
- tolerant partial selectors and bounded discovery-limit clamping
- clearer short benchmark guidance

This before/after comparison is directional evidence because fresh agents made
different implementation choices. The paired final table is the stronger
comparison.

## Remaining lesson

Discovery is now the largest obvious avoidable cost. Epic 4 made seven separate
search calls because `ravens_discover` accepts one query at a time. The next
small product experiment should accept a bounded list of discovery queries and
return all results under one revision. That would preserve deterministic
ranking while letting an agent ask for `shipping`, `delivery`, `backorder`, and
the namespace inventory in one round trip.

Do not claim that 2Ravens always halves token use from this one lifecycle.
Claim only that the current entity-authoring path was safe, completed all three
jobs without repair or repeated source, and substantially beat the paired
files condition in this frozen probe.
