defmodule TwoRavens.Source.Function do
  @moduledoc "A public function and its ordered source clauses."

  @enforce_keys [:id, :module, :name, :arity, :clauses, :source, :evidence]
  defstruct [:id, :module, :name, :arity, :clauses, :source, :evidence]

  @type t :: %__MODULE__{
          id: String.t(),
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          clauses: [TwoRavens.Source.Clause.t()],
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
