# Phase 2 — Behavior-first review

## Status

Planned. Product development begins after Phase 1 passes its exit criteria.

## Product promise

Show a reviewer what a code change does and what it can affect before requiring
them to read every line of the diff.

The product should help a reviewer answer:

- What behavior changed?
- Which entry points and flows can reach the change?
- Which downstream effects can it cause?
- Which application or OTP boundaries are crossed?
- Which clauses and branches changed?
- Which tests provide evidence?
- What is uncovered, unresolved, or uncertain?

## Why this is valuable

AI can create changes faster than humans can build a mental model of them. A
diff shows edited text, but it does not directly show the behavioral role of
that text or its effect on the surrounding system.

Phase 2 turns the Phase 1 evidence graph into a human approval surface. Its
value is faster orientation, better identification of missing tests and
unintended dependencies, and greater confidence when reviewing unfamiliar or
AI-generated changes.

## Target user

The initial user is a developer reviewing a working-tree change or commit in an
Elixir repository. Pull-request integration is useful later, but it is not
required to validate the core review workflow.

## Primary workflow

1. Open a working-tree change or commit.
2. See a concise summary of changed entry points and likely affected behavior.
3. Inspect important upstream and downstream flows.
4. Inspect changed clauses, guards, and boundaries.
5. Inspect tests, observed paths, and missing evidence.
6. Drill into exact source and the original diff where needed.
7. Copy the selected review context for discussion or an AI agent.

The UI should lead from explanation to evidence to source. It must not prevent
reviewers from inspecting the underlying diff.

## Required capabilities

### Change model

2Ravens needs comparable graph perspectives:

- Base or `HEAD` graph
- Selected commit or working-tree graph
- Change projection containing added, removed, and modified facts

This model should support changes to nodes, relationships, clauses, and
evidence—not only changed files.

### Review projection

For one change, the UI should present:

- Changed public entry points and behaviors
- Important affected flows
- Added, removed, or changed relationships
- Clause and guard changes
- Side effects and boundary crossings
- Relevant tests and examples
- Uncovered or weakly supported paths
- Freshness, provenance, and uncertainty
- Source and diff drill-down

The first version should show one curated projection. A configurable graph
workbench is not required.

### Behavior language

“Behavior changed” is a strong claim. The UI must distinguish:

- A syntactic change to implementation
- A statically inferred effect
- A compiler-confirmed relationship
- Behavior observed in tests
- Behavior observed at runtime

When evidence supports only potential impact, the UI must say “may affect” or
equivalent language.

### Progressive disclosure

The default view should remain small:

```text
Change summary
→ affected flows and boundaries
→ clauses and test evidence
→ exact source and diff
```

Large raw graphs, every transitive caller, and low-value implementation details
should be collapsed until requested.

## Delivery milestones

### 1. Review contract

- Select representative changes with different shapes and risks.
- Define the questions a reviewer must answer for each change.
- Design static examples of the complete review flow.
- Define language for confirmed, observed, inferred, and unknown impact.

### 2. Before-and-after projection

- Compare base and changed graph perspectives.
- Identify changed symbols, relationships, clauses, and evidence.
- Rank affected flows using the context work from Phase 1.

### 3. Minimal review UI

- Open one local change.
- Show the concise change summary and affected-flow projection.
- Support test, evidence, source, and diff drill-down.
- Support copying the selected context.

### 4. Review validation

- Run timed reviews with and without 2Ravens.
- Compare understanding, risks found, evidence inspected, and errors.
- Improve the projection before adding broader repository navigation.

### 5. Workflow integration

- Add commit and branch selection.
- Consider pull-request integration after the local workflow proves useful.
- Add navigation between related changes only when demanded by real reviews.

## Validation

Use real changes with known intent, affected flows, tests, and review findings.
Include small local edits, cross-application changes, OTP behavior changes, and
changes with missing tests.

Measure:

- Time to an accurate explanation of the change
- Correct identification of affected behavior and boundaries
- Important risks and missing tests found
- Source files and diff regions opened
- Incorrect impact claims accepted by the reviewer
- Reviewer confidence before and after source inspection

The goal is not simply a faster review. It is a faster review without reducing
the quality of the human approval decision.

## Risks

- Attractive visualizations can create false confidence in incomplete facts.
- Transitive dependency graphs can overwhelm rather than clarify.
- Static analysis may describe possible impact as actual runtime behavior.
- Generated summaries may hide the evidence a reviewer needs to challenge.
- Reviewers may trust the tool instead of inspecting disclosed uncertainty.

The design must make uncertainty and source drill-down normal parts of the
workflow.

## Non-goals

Phase 2 does not include:

- Replacing the source diff
- Automatically approving changes
- A full IDE or code editor
- A general-purpose graph database interface
- Proof of runtime effects that have not been observed
- Continuous runtime tracing
- Replacing GitHub or another code-review system

## Exit criteria

Phase 2 is complete when reviewers can use 2Ravens to answer the important
behavior and impact questions for representative changes:

- More quickly than the baseline workflow
- With equal or better accuracy
- Without treating inferred impact as confirmed behavior
- With clear access to tests, uncertainty, source, and the original diff
- With measurable improvement in finding important risks or missing evidence

Passing this gate demonstrates that the static graph supports human
understanding and provides the UI foundation for system exploration.
