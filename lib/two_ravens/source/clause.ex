defmodule TwoRavens.Source.Clause do
  @moduledoc "One ordered function clause with its derived facts."

  @enforce_keys [
    :id,
    :function_id,
    :ordinal,
    :fingerprint,
    :patterns,
    :guard,
    :calls,
    :comparisons,
    :source,
    :evidence
  ]
  defstruct [
    :id,
    :function_id,
    :ordinal,
    :fingerprint,
    :patterns,
    :guard,
    :calls,
    :comparisons,
    :source,
    :evidence
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          function_id: String.t(),
          ordinal: pos_integer(),
          fingerprint: String.t(),
          patterns: [String.t()],
          guard: String.t() | nil,
          calls: [TwoRavens.Source.Call.t()],
          comparisons: [TwoRavens.Source.Comparison.t()],
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
