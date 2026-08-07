defmodule TwoRavens.Authoring.Proposal do
  @moduledoc false

  @enforce_keys [
    :kind,
    :project,
    :files,
    :before_files,
    :base_hashes,
    :manifest,
    :manifest_hash,
    :graph,
    :details
  ]
  defstruct [
    :kind,
    :project,
    :files,
    :before_files,
    :base_hashes,
    :manifest,
    :manifest_hash,
    :graph,
    :details
  ]

  @type t :: %__MODULE__{
          kind: :create_module | :create_function | :set,
          project: TwoRavens.Project.t(),
          files: %{String.t() => String.t()},
          before_files: %{String.t() => String.t()},
          base_hashes: %{String.t() => String.t() | nil},
          manifest: TwoRavens.Manifest.t(),
          manifest_hash: String.t(),
          graph: TwoRavens.Graph.t(),
          details: map()
        }
end
