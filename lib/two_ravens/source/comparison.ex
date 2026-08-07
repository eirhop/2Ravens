defmodule TwoRavens.Source.Comparison do
  @moduledoc "An editable comparison derived from a function guard."

  @enforce_keys [
    :id,
    :function_id,
    :clause_id,
    :clause_fingerprint,
    :fingerprint,
    :operator,
    :left,
    :right,
    :source,
    :evidence
  ]
  defstruct [
    :id,
    :function_id,
    :clause_id,
    :clause_fingerprint,
    :fingerprint,
    :operator,
    :left,
    :right,
    :source,
    :evidence
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          function_id: String.t(),
          clause_id: String.t(),
          clause_fingerprint: String.t(),
          fingerprint: String.t(),
          operator: String.t(),
          left: String.t(),
          right: String.t(),
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
