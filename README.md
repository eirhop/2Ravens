# 2Ravens

> Trusted code context and runtime understanding for Elixir, OTP, humans, and AI.

2Ravens is an experimental developer tool that builds a semantic evidence graph
of an Elixir repository. It uses that graph to help AI agents retrieve precise
context, help humans review behavior changes, and eventually make OTP systems
easier to explore and debug.

The product is planned in three phases:

1. **AI context** — return the smallest trustworthy context needed for a task.
2. **Behavior-first review** — show humans what changed and what it affects.
3. **Runtime understanding** — make systems explorable and debugging sessions
   explainable.

Source code and Git remain authoritative. Tests and observed runtime events
provide behavioral evidence. 2Ravens is a regenerable understanding layer over
those sources.

## Documentation

- [Documentation index](docs/README.md)
- [Vision](docs/VISION.md)
- [Product plan](docs/PRODUCT.md)
- [Roadmap](docs/ROADMAP.md)
- [Architecture](docs/ARCHITECTURE.md)

## Concepts

```text
2Ravens
├── Munin   # Memory — evidence graph and synchronization
└── Hugin   # Thought — context, explanation, and visualization
```

These are conceptual responsibilities, not committed OTP application
boundaries.

## Status

Product planning and Phase 1 research.
