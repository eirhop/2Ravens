defmodule TwoRavens.Source.Fragment do
  @moduledoc "A deterministic graph fragment for one managed file."

  @enforce_keys [:path, :hash, :module, :functions, :tests, :unsupported]
  defstruct [:path, :hash, :module, :functions, :tests, :unsupported]

  @type t :: %__MODULE__{
          path: String.t(),
          hash: String.t(),
          module: TwoRavens.Source.Module.t(),
          functions: [TwoRavens.Source.Function.t()],
          tests: [TwoRavens.Source.Test.t()],
          unsupported: [String.t()]
        }
end
