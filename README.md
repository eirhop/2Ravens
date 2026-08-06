# 2Ravens

> A local execution map for Elixir, OTP, humans, and AI.

2Ravens parses an Elixir repository into a deterministic graph of applications,
modules, functions, clauses, calls, values, tests, OTP processes, messages, and
effects. AI agents and humans query slices of that graph instead of rebuilding
the same understanding through repeated searches and file reads.

The product is planned in three phases:

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

Product planning and Phase 1 technical validation.
