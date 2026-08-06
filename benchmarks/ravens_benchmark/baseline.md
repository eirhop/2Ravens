# Without-Ravens baseline

## Purpose

Measure how a capable coding agent gathers repository context before 2Ravens
exists. These results become the comparison point for the same frozen tasks
using `mix ravens`.

No baseline numbers are recorded until a blinded run is performed. Invented or
retrospective measurements are not acceptable.

## Isolation

For every run:

1. Create a clean worktree at the recorded fixture revision.
2. Give the agent only the selected prompt from [`tasks.exs`](tasks.exs).
3. Set the working directory to `dev/benchmark_app`.
4. Tell the agent not to use 2Ravens and not to read directories outside the
   benchmark app.
5. Use the same model, reasoning effort, tool permissions, and completion rule
   for the later with-Ravens comparison.
6. Use a fresh task and worktree for every run so earlier answers cannot leak.

The acceptance oracle remains outside the agent's allowed working directory.

## Recorded run data

Record one JSON document per run under `baselines/` with:

```text
run_id
fixture_revision
task_id
condition: without_ravens | with_ravens
agent_product
model
reasoning_effort
tool_permissions
started_at
finished_at
final_answer
transcript_location
search_operations
file_list_operations
source_reads
shell_exploration_operations
ravens_queries
total_context_bytes
time_to_first_correct_answer_or_edit
```

An exploration operation is one agent-initiated repository navigation tool
call. A batched call counts once and retains its number of individual queries
as separate supporting data. Compilation and tests used only for final
verification are recorded but do not count as exploration.

## Scoring

Score each answer against [`expected.exs`](expected.exs):

- Required-node recall
- Required-relationship recall
- Important-path recall
- Correct branch conditions and outcomes
- Correct state and external-effect ordering
- Correct uncertainty, boundary, and frontier reporting
- Irrelevant repository-owned nodes or source
- Incorrect assumptions
- Task completion correctness

Do not set numerical product targets until the first baseline set exists.
Ravens must preserve or improve correctness while reducing exploration and
duplicated context.

## Initial run set

Run every frozen task once before graph implementation. If results vary enough
to affect a product decision, repeat that task with fresh agents and report the
distribution rather than selecting the best run.

The first real-repository dogfooding run analyzes 2Ravens itself after the graph
kernel exists. A larger external Elixir repository is required before the
Phase 1 gate; this controlled fixture is not evidence of generality.
