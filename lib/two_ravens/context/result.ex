defmodule TwoRavens.Context.Result do
  @moduledoc "Compact persisted context with optional source materialization."

  @enforce_keys [:focus, :entity, :freshness, :include]
  defstruct [
    :focus,
    :entity,
    :freshness,
    :include,
    :function,
    :source,
    clauses: [],
    callers: [],
    caller_relations: [],
    upstream: [],
    callees: [],
    callee_relations: [],
    tests: [],
    derived_test_relations: [],
    requested_tests: [],
    intents: [],
    evidence: [],
    editable_comparisons: [],
    unsupported: [],
    frontier: []
  ]

  @type t :: %__MODULE__{
          focus: String.t(),
          entity: map(),
          freshness: map(),
          include: [atom()],
          function: TwoRavens.Source.Function.t() | nil,
          source: String.t() | nil,
          clauses: [TwoRavens.Source.Clause.t()],
          callers: [String.t()],
          caller_relations: [map()],
          upstream: [String.t()],
          callees: [String.t()],
          callee_relations: [map()],
          tests: [String.t()],
          derived_test_relations: [map()],
          requested_tests: [map()],
          intents: [map()],
          evidence: [map()],
          editable_comparisons: [map()],
          unsupported: [String.t()],
          frontier: [String.t()]
        }
end
