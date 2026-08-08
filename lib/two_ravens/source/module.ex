defmodule TwoRavens.Source.Module do
  @moduledoc "A module derived from one managed source file."

  @enforce_keys [:id, :name, :source, :evidence]
  defstruct [:id, :name, :documentation, :source, :evidence]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          documentation: String.t() | false | nil,
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
