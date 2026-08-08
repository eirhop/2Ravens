defmodule TwoRavens.Semantic.Origin do
  @moduledoc "Fixed provenance values accepted by persistent semantic memory."

  @values [
    :requested,
    :source_derived,
    :compiler_confirmed,
    :test_observed,
    :runtime_observed,
    :reconstructed
  ]

  @type t ::
          :requested
          | :source_derived
          | :compiler_confirmed
          | :test_observed
          | :runtime_observed
          | :reconstructed

  @doc "Returns all accepted origins."
  @spec values() :: [t()]
  def values, do: @values

  @doc "Converts a fixed origin to its storage representation."
  @spec dump(t()) :: String.t()
  def dump(origin) when origin in @values, do: Atom.to_string(origin)

  @doc "Loads only a fixed origin without creating atoms."
  @spec load(String.t()) :: {:ok, t()} | {:error, map()}
  def load(value) when is_binary(value) do
    case Enum.find(@values, &(Atom.to_string(&1) == value)) do
      nil -> {:error, %{code: :invalid_semantic_origin, value: value}}
      origin -> {:ok, origin}
    end
  end
end
