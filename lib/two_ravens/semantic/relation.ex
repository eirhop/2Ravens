defmodule TwoRavens.Semantic.Relation do
  @moduledoc "A typed semantic relationship with fixed origin and confidence."

  @enforce_keys [:source, :type, :target, :origin, :confidence, :revision]
  defstruct [:source, :type, :target, :origin, :confidence, :revision, :source_range]

  @type type :: :defines | :calls | :tested_by | :intended_to_test
  @type confidence :: :asserted | :derived | :confirmed | :unknown
  @type t :: %__MODULE__{
          source: String.t(),
          type: type(),
          target: String.t(),
          origin: TwoRavens.Semantic.Origin.t(),
          confidence: confidence(),
          revision: String.t(),
          source_range: TwoRavens.SourceRange.t() | nil
        }
end
