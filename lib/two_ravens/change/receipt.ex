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
    :selected,
    :selected_from,
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
          selected: [map()] | nil,
          selected_from: map() | nil,
          working_tree_changed: boolean()
        }

  @doc false
  @spec dump(t()) :: binary()
  def dump(%__MODULE__{} = receipt) do
    receipt
    |> Map.from_struct()
    |> Jason.encode!()
  end

  @doc false
  @spec load(binary()) :: {:ok, t()} | {:error, map()}
  def load(payload) when is_binary(payload) do
    with {:ok, decoded} <- decode(payload),
         :ok <- exact_keys(decoded),
         :ok <- validate(decoded),
         {:ok, entities} <- load_entities(decoded["entities"]),
         {:ok, qualification} <- load_qualification(decoded["qualification"]),
         {:ok, selected_from} <- load_selected_from(decoded["selected_from"]) do
      {:ok,
       %__MODULE__{
         status: :applied,
         operation_count: decoded["operation_count"],
         draft: nil,
         draft_version: nil,
         revision: decoded["revision"],
         entities: entities,
         relationships: decoded["relationships"],
         qualification: qualification,
         affected_paths: decoded["affected_paths"],
         diagnostics: decoded["diagnostics"],
         selected: decoded["selected"],
         selected_from: selected_from,
         working_tree_changed: true
       }}
    end
  rescue
    _error -> {:error, %{code: :accepted_request_corrupt}}
  end

  defp decode(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, %{code: :accepted_request_corrupt}}
    end
  end

  defp exact_keys(decoded) do
    expected =
      ~w(status operation_count draft draft_version revision entities relationships qualification affected_paths diagnostics selected selected_from working_tree_changed)

    if is_map(decoded) and Enum.sort(Map.keys(decoded)) == Enum.sort(expected),
      do: :ok,
      else: {:error, %{code: :accepted_request_corrupt}}
  end

  defp validate(decoded) do
    checks = [
      decoded["status"] == "applied",
      is_integer(decoded["operation_count"]) and decoded["operation_count"] > 0,
      is_nil(decoded["draft"]),
      is_nil(decoded["draft_version"]),
      is_binary(decoded["revision"]),
      is_map(decoded["relationships"]),
      is_integer(decoded["affected_paths"]) and decoded["affected_paths"] >= 0,
      is_list(decoded["diagnostics"]),
      is_list(decoded["selected"]),
      decoded["working_tree_changed"] == true
    ]

    if Enum.all?(checks),
      do: :ok,
      else: {:error, %{code: :accepted_request_corrupt}}
  end

  @entity_actions %{
    "create" => :create,
    "replace" => :replace,
    "patch" => :patch,
    "set" => :set,
    "delete" => :delete,
    "rename" => :rename,
    "move" => :move
  }

  defp load_entities(entities) when is_map(entities) do
    if Enum.all?(entities, fn {key, count} ->
         Map.has_key?(@entity_actions, key) and is_integer(count) and count >= 0
       end) do
      {:ok, Map.new(entities, fn {key, count} -> {Map.fetch!(@entity_actions, key), count} end)}
    else
      {:error, %{code: :accepted_request_corrupt}}
    end
  end

  defp load_entities(_entities), do: {:error, %{code: :accepted_request_corrupt}}

  defp load_qualification(%{
         "format" => format,
         "compile" => compile,
         "tests" => tests,
         "commands" => commands,
         "output_bytes" => output_bytes
       })
       when is_integer(commands) and commands >= 0 and is_integer(output_bytes) and
              output_bytes >= 0 do
    with {:ok, format} <- load_status(format),
         {:ok, compile} <- load_status(compile),
         {:ok, tests} <- load_status(tests) do
      {:ok,
       %{
         format: format,
         compile: compile,
         tests: tests,
         commands: commands,
         output_bytes: output_bytes
       }}
    end
  end

  defp load_qualification(_qualification),
    do: {:error, %{code: :accepted_request_corrupt}}

  defp load_status("pass"), do: {:ok, :pass}
  defp load_status("fail"), do: {:ok, :fail}
  defp load_status("unknown"), do: {:ok, :unknown}
  defp load_status("not_run"), do: {:ok, :not_run}
  defp load_status(_status), do: {:error, %{code: :accepted_request_corrupt}}

  defp load_selected_from(%{"revision" => revision}) when is_binary(revision),
    do: {:ok, %{revision: revision}}

  defp load_selected_from(_selected_from),
    do: {:error, %{code: :accepted_request_corrupt}}
end
