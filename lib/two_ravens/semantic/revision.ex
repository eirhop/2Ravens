defmodule TwoRavens.Semantic.Revision do
  @moduledoc "A versioned semantic-memory revision for one managed working hash."

  @enforce_keys [:id, :working_hash, :created_at, :intent_status]
  defstruct [:id, :working_hash, :git_revision, :created_at, :intent_status, :reason]

  @type intent_status :: :available | :unavailable
  @type t :: %__MODULE__{
          id: String.t(),
          working_hash: String.t(),
          git_revision: String.t() | nil,
          created_at: String.t(),
          intent_status: intent_status(),
          reason: atom() | nil
        }

  @doc "Builds a deterministic revision identity from managed source."
  @spec from_repository(TwoRavens.Repository.Revision.t(), intent_status(), atom() | nil) :: t()
  def from_repository(repository_revision, intent_status, reason \\ nil) do
    %__MODULE__{
      id: "revision:r_" <> binary_part(repository_revision.working_hash, 0, 20),
      working_hash: repository_revision.working_hash,
      git_revision: repository_revision.git_revision,
      created_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      intent_status: intent_status,
      reason: reason
    }
  end
end
