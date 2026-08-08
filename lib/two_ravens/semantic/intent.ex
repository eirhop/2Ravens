defmodule TwoRavens.Semantic.Intent do
  @moduledoc "Requested knowledge attached to an accepted semantic entity."

  @enforce_keys [:subject, :text, :kind, :operation, :revision, :origin]
  defstruct [:subject, :text, :kind, :operation, :revision, :origin]

  @type t :: %__MODULE__{
          subject: String.t(),
          text: String.t(),
          kind: :purpose | :change_reason,
          operation: String.t(),
          revision: String.t(),
          origin: :requested
        }
end
