defmodule TwoRavens.Graph.Edge do
  @moduledoc "A typed, source-derived graph relationship."

  @enforce_keys [:kind, :from, :to, :evidence]
  defstruct [:kind, :from, :to, :source, :evidence]

  @type t :: %__MODULE__{
          kind: :defines | :calls | :tested_by,
          from: String.t(),
          to: String.t(),
          source: TwoRavens.SourceRange.t() | nil,
          evidence: TwoRavens.Evidence.t()
        }
end
