defmodule TwoRavens.Change.Error do
  @moduledoc "A structured entity-authoring request error."

  @enforce_keys [:code]
  defstruct [:code, :operation, :target, :reason, :details]

  @type t :: %__MODULE__{
          code: atom(),
          operation: non_neg_integer() | nil,
          target: String.t() | nil,
          reason: term(),
          details: map() | nil
        }

  @doc false
  @spec from(map() | atom()) :: t()
  def from(%{code: code} = error) do
    %__MODULE__{
      code: code,
      operation: Map.get(error, :operation),
      target: Map.get(error, :target),
      reason: Map.get(error, :reason),
      details: Map.drop(error, [:code, :operation, :target, :reason])
    }
  end

  def from(code) when is_atom(code), do: %__MODULE__{code: code}
end
