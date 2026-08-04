# 2Ravens

> Graph-based code understanding and runtime visualization for Elixir, OTP and AI.

2Ravens is an experimental developer tool that helps humans and AI understand Elixir systems through code graphs, execution flows, process state, and runtime visualization.

Instead of navigating files, logs, and grep results, 2Ravens builds a semantic graph of your application so both humans and AI can quickly understand:

- What changed
- What behavior is affected
- How data flows through the system
- Which OTP processes participate
- What state changes
- Which tests cover the behavior
- What context an AI actually needs

## Vision

The long-term goal is to make understanding software dramatically easier in the AI era, where humans review and reason about systems that are increasingly written by AI.

See the full vision:

- [Vision](docs/VISION.md)

## Planned architecture

```
2Ravens
├── Hugin   # Thought — reasoning, MCP, visualization
└── Munin   # Memory — graph index and synchronization
```

## Status

Early design and research.

