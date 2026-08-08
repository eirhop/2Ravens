defmodule TwoRavens.Source.Function do
  @moduledoc "A function identity and its ordered source clauses."

  @enforce_keys [:id, :module, :name, :arity, :clauses, :source, :evidence]
  defstruct [
    :id,
    :module,
    :name,
    :arity,
    :definition_kind,
    :visibility,
    :documentation,
    :specifications,
    :clauses,
    :source,
    :evidence
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          definition_kind: :def,
          visibility: :public | :private,
          documentation: String.t() | false | nil,
          specifications: [String.t()],
          clauses: [TwoRavens.Source.Clause.t()],
          source: TwoRavens.SourceRange.t(),
          evidence: TwoRavens.Evidence.t()
        }
end
