# 2Ravens

> A local execution map for Elixir, OTP, humans, and AI.

2Ravens is a local semantic authoring and understanding layer for Elixir. Its
first MVP creates and edits a constrained greenfield project through ordinary
Elixir, then reads the generated source back into a deterministic graph. Later
phases extend that graph to arbitrary repositories, behavior review, and runtime
understanding.

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

The [greenfield semantic-authoring MVP](docs/scopes/01-greenfield-authoring-mvp.md)
is implemented. It manages only source created through 2Ravens, rebuilds its
graph on every command, and qualifies explicit writes in an isolated project.
