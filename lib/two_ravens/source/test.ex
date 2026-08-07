defmodule TwoRavens.Source.Test do
  @moduledoc "An ExUnit test and the direct calls derived from its body."

  @enforce_keys [:id, :module, :name, :calls, :source, :evidence]
  defstruct [:id, :module, :name, :calls, :source, :evidence]

  @type t :: %__MODULE__{
          id: String.t(),
          module: String.t(),
          name: String.t(),
          calls: [TwoRavens.Source.Call.t()],
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
