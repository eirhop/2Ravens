# 2Ravens

> A local execution map for Elixir, OTP, humans, and AI.

2Ravens is a local semantic authoring and understanding layer for Elixir. Its
first MVP safely creates and edits a constrained greenfield project through
ordinary Elixir. Local semantic memory is implemented, and the active
experiment now batches exact module, function, clause, and module-form changes
into repairable entity drafts. Later phases extend the graph to arbitrary
repositories, behavior review, and runtime understanding.

After the write-first MVP foundation, the product is planned in three phases:

1. **AI context — what could happen?** Return a precise possible execution
   graph around one or more points of focus.
2. **Behavior-first review — what possibilities changed?** Compare execution
   graphs before and after a code change.
3. **Runtime understanding — what actually happened?** Overlay an observed
   execution on the possible graph.

Every core capability runs locally after installation. 2Ravens requires no
account, API key, cloud service, embedding model, or external database.

## Documentation

- [Documentation index](docs/README.md)
- [Vision](docs/VISION.md)
- [Product plan](docs/PRODUCT.md)
- [Context query](docs/QUERY.md)
- [Semantic editing](docs/EDITING.md)
- [Entity authoring API](docs/ENTITY_AUTHORING.md)
- [Authoring-time semantic memory](docs/SEMANTIC_MEMORY.md)
- [Roadmap](docs/ROADMAP.md)
- [Architecture](docs/ARCHITECTURE.md)

## Concepts

```text
2Ravens
├── Munin   # Memory — repository graph and synchronization
└── Hugin   # Thought — graph slices, explanation, and visualization
```

These are conceptual responsibilities, not committed OTP application
boundaries.

## Status

The greenfield authoring, persistent semantic-memory, and entity-based batch
authoring foundations are implemented. Scope 04 adds flat project-bound MCP
tools, canonical discovery, batched exact context, same-call proof, retained
request repair, and first-class test editing while ordinary source remains
authoritative and recoverable.

The final frozen three-job Luna lifecycle used 48.4% fewer total tokens, 45.5%
fewer tool wrappers, and 38.4% less wall time than the paired files condition.
Both conditions completed correctly. This reverses the earlier unfavorable
probe, but the replication gate remains open; see the
[recorded lifecycle](benchmarks/entity_authoring/lifecycle_luna_2026-08-08.md).
