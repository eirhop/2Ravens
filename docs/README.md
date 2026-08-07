# Documentation

Start with these documents:

- [Vision](VISION.md) explains why 2Ravens should exist and the long-term
  destination.
- [Product plan](PRODUCT.md) explains how the three product phases form one
  coherent path.
- [Context query](QUERY.md) defines how an AI explores the graph through one
  flexible operation.
- [Semantic editing](EDITING.md) defines compact candidate changes, their
  validation boundary, and the managed-authoring MVP contract.
- [Roadmap](ROADMAP.md) records the order of work and the gate between phases.
- [Architecture](ARCHITECTURE.md) defines the local graph, execution envelope,
  evidence model, and current technical direction.

Each product phase has its own plan:

1. [AI context](phases/01-ai-context.md)
2. [Behavior-first review](phases/02-behavior-review.md)
3. [Runtime understanding](phases/03-runtime-understanding.md)

Implementation starts from bounded development scopes:

1. [Greenfield semantic authoring MVP](scopes/01-greenfield-authoring-mvp.md)
2. [Copy-paste implementation prompt](scopes/01-implementation-prompt.md)

## Document boundaries

- `VISION.md` owns the enduring problem, destination, and principles.
- `PRODUCT.md` owns the product strategy and relationship between phases.
- `QUERY.md` owns the public context-query contract and usage scenarios.
- `EDITING.md` owns the semantic-change contract, CLI shape, validation, and
  implementation gate.
- `scopes/` owns developer-ready implementation boundaries and acceptance
  criteria without replacing the product roadmap.
- `phases/` owns the promise, scope, validation, and exit criteria for each
  phase.
- `ROADMAP.md` owns sequencing and current status.
- `ARCHITECTURE.md` owns graph semantics, evidence, algorithms, and shared
  technical constraints.

Implementation decisions that require evidence remain open until the relevant
phase produces that evidence.
