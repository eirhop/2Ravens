defmodule TwoRavens.Semantic.Operation do
  @moduledoc "An accepted authoring operation and its source revision transition."

  @enforce_keys [:id, :action, :result_revision, :result, :status, :created_at]
  defstruct [:id, :action, :base_revision, :result_revision, :result, :status, :created_at]

  @type t :: %__MODULE__{
          id: String.t(),
          action: :create_module | :create_function | :set,
          base_revision: String.t() | nil,
          result_revision: String.t(),
          result: String.t(),
          status: :accepted,
          created_at: String.t()
        }

  @doc "Builds a bounded accepted operation identity."
  @spec accepted(atom(), String.t() | nil, String.t(), String.t()) :: t()
  def accepted(action, base_revision, result_revision, result) do
    %__MODULE__{
      id: "operation:o_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
      action: action,
      base_revision: base_revision,
      result_revision: result_revision,
      result: result,
      status: :accepted,
      created_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end
end
