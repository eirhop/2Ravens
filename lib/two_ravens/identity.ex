defmodule TwoRavens.Identity do
  @moduledoc "Canonical semantic identities shared by source and graph layers."

  alias TwoRavens.Repository

  @doc "Returns a canonical module identity."
  @spec module(String.t()) :: String.t()
  def module(module), do: "module:#{module}"

  @doc "Returns a canonical function identity."
  @spec function(String.t(), String.t(), non_neg_integer()) :: String.t()
  def function(module, name, arity), do: "function:#{module}.#{name}/#{arity}"

  @doc "Returns a deterministic structural fingerprint."
  @spec fingerprint(term()) :: String.t()
  def fingerprint(term) do
    term
    |> :erlang.term_to_binary()
    |> Repository.hash()
    |> binary_part(0, 16)
  end
end
