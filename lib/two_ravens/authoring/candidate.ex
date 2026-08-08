defmodule TwoRavens.Authoring.Candidate do
  @moduledoc "An immutable, process-local source candidate and its evidence."

  @enforce_keys [
    :kind,
    :root,
    :files,
    :base_hashes,
    :base_working_hash,
    :manifest,
    :manifest_hash,
    :diff,
    :graph,
    :evidence,
    :details,
    :applied,
    :semantic
  ]
  defstruct [
    :kind,
    :root,
    :files,
    :base_hashes,
    :base_working_hash,
    :manifest,
    :manifest_hash,
    :diff,
    :graph,
    :evidence,
    :details,
    :applied,
    :semantic
  ]

  @type t :: %__MODULE__{
          kind: :create_module | :create_function | :set,
          root: String.t(),
          files: %{String.t() => String.t()},
          base_hashes: %{String.t() => String.t() | nil},
          base_working_hash: String.t(),
          manifest: TwoRavens.Manifest.t(),
          manifest_hash: String.t(),
          diff: String.t(),
          graph: TwoRavens.Graph.t(),
          evidence: TwoRavens.Qualification.Evidence.t(),
          details: map(),
          applied: boolean(),
          semantic: map()
        }
end
