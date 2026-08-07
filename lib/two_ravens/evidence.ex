defmodule TwoRavens.Evidence do
  @moduledoc "Source-derived evidence attached to a graph fact."

  @enforce_keys [:origin, :confidence, :freshness]
  defstruct [:origin, :confidence, :freshness]

  @type t :: %__MODULE__{
          origin: :source_parser | :compiler | :test,
          confidence: :derived | :confirmed,
          freshness: :current | :stale | :missing
        }

  @doc "Returns current evidence derived directly from managed source."
  @spec derived_source() :: t()
  def derived_source do
    %__MODULE__{origin: :source_parser, confidence: :derived, freshness: :current}
  end
end
