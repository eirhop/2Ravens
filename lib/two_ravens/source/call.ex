defmodule TwoRavens.Source.Call do
  @moduledoc "A local or explicit remote call observed in source."

  @enforce_keys [:caller_id, :module, :name, :arity, :source, :evidence]
  defstruct [:caller_id, :module, :name, :arity, :imports, :source, :evidence]

  @type t :: %__MODULE__{
          caller_id: String.t(),
          module: String.t() | nil,
          name: String.t(),
          arity: non_neg_integer(),
          imports: [String.t()] | nil,
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
