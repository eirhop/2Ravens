defmodule TwoRavens.Context.Result do
  @moduledoc "Compact function-focused context returned by the MVP query."

  @enforce_keys [
    :focus,
    :function,
    :clauses,
    :callers,
    :upstream,
    :callees,
    :tests,
    :editable_comparisons,
    :freshness,
    :unsupported,
    :frontier,
    :source
  ]
  defstruct [
    :focus,
    :function,
    :clauses,
    :callers,
    :upstream,
    :callees,
    :tests,
    :editable_comparisons,
    :freshness,
    :unsupported,
    :frontier,
    :source
  ]

  @type t :: %__MODULE__{
          focus: String.t(),
          function: TwoRavens.Source.Function.t(),
          clauses: [TwoRavens.Source.Clause.t()],
          callers: [String.t()],
          upstream: [String.t()],
          callees: [String.t()],
          tests: [String.t()],
          editable_comparisons: [map()],
          freshness: map(),
          unsupported: [String.t()],
          frontier: [String.t()],
          source: String.t()
        }
end
