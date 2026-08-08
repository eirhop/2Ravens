defmodule TwoRavens.Semantic.Evidence do
  @moduledoc "Evidence for one entity, operation, or semantic revision."

  @enforce_keys [:type, :status, :origin, :revision]
  defstruct [:subject, :operation, :type, :status, :origin, :revision, :reason]

  @type status :: :pass | :fail | :unknown | :not_run
  @type t :: %__MODULE__{
          subject: String.t() | nil,
          operation: String.t() | nil,
          type: atom(),
          status: status(),
          origin: TwoRavens.Semantic.Origin.t(),
          revision: String.t(),
          reason: atom() | String.t() | nil
        }
end
