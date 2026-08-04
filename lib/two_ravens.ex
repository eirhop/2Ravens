defmodule TwoRavens do
  @moduledoc """
  Tools for understanding Elixir systems through code graphs, execution flows,
  process state, and runtime visualization.
  """

  @doc """
  Returns the project name.

  ## Examples

      iex> TwoRavens.name()
      "2Ravens"

  """
  @spec name() :: String.t()
  def name, do: "2Ravens"
end
