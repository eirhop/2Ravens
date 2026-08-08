defmodule TwoRavens.Change.Receipt do
  @moduledoc "Compact result of one ordered entity-authoring request."

  @enforce_keys [:status, :operation_count, :working_tree_changed]
  defstruct [
    :status,
    :operation_count,
    :draft,
    :draft_version,
    :revision,
    :entities,
    :relationships,
    :qualification,
    :affected_paths,
    :diagnostics,
    :working_tree_changed
  ]

  @type status :: :applied | :ready | :needs_changes
  @type t :: %__MODULE__{
          status: status(),
          operation_count: pos_integer(),
          draft: String.t() | nil,
          draft_version: pos_integer() | nil,
          revision: String.t() | nil,
          entities: map() | nil,
          relationships: map() | nil,
          qualification: map() | nil,
          affected_paths: non_neg_integer() | nil,
          diagnostics: [map()] | nil,
          working_tree_changed: boolean()
        }
end
