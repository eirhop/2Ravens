defmodule TwoRavens.Qualifier.Result do
  @moduledoc false

  @enforce_keys [:files, :graph, :evidence]
  defstruct [:files, :graph, :evidence]

  @type t :: %__MODULE__{
          files: %{String.t() => String.t()},
          graph: TwoRavens.Graph.t(),
          evidence: TwoRavens.Qualification.Evidence.t()
        }
end
