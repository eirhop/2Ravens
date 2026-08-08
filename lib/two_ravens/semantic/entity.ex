defmodule TwoRavens.Semantic.Entity do
  @moduledoc "A stable opaque entity identity separate from its mutable semantic key."

  alias TwoRavens.Repository

  @enforce_keys [:id, :kind, :semantic_key, :lifecycle, :origin]
  defstruct [:id, :kind, :semantic_key, :lifecycle, :origin]

  @type lifecycle :: :active | :retired | :unresolved
  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          semantic_key: String.t(),
          lifecycle: lifecycle(),
          origin: TwoRavens.Semantic.Origin.t()
        }

  @doc "Generates a bounded URL-safe identity for an accepted entity."
  @spec generate_id() :: String.t()
  def generate_id do
    "entity:n_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
  end

  @doc "Returns a deterministic identity that discloses source reconstruction."
  @spec reconstructed_id(String.t(), String.t()) :: String.t()
  def reconstructed_id(kind, semantic_key) do
    digest = Repository.hash(kind <> <<0>> <> semantic_key) |> binary_part(0, 20)
    "entity:reconstructed_" <> digest
  end
end
