defmodule TwoRavens.Repository.Revision do
  @moduledoc "A deterministic revision assembled from managed source."

  @enforce_keys [:working_hash, :file_hashes]
  defstruct [:git_revision, :working_hash, :file_hashes]

  @type t :: %__MODULE__{
          git_revision: String.t() | nil,
          working_hash: String.t(),
          file_hashes: %{String.t() => String.t() | :missing}
        }
end
