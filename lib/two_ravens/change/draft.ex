defmodule TwoRavens.Change.Draft do
  @moduledoc "An immutable persisted version of an entity-authoring candidate."

  alias TwoRavens.Change.Operation

  @enforce_keys [
    :id,
    :version,
    :base_revision,
    :base_working_hash,
    :base_hashes,
    :manifest_hash,
    :manifest,
    :files,
    :before_files,
    :operations,
    :status,
    :diagnostics,
    :expires_at
  ]
  defstruct [
    :id,
    :version,
    :base_revision,
    :base_working_hash,
    :base_hashes,
    :manifest_hash,
    :manifest,
    :files,
    :before_files,
    :operations,
    :status,
    :diagnostics,
    :qualification,
    :expires_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          base_revision: String.t(),
          base_working_hash: String.t(),
          base_hashes: map(),
          manifest_hash: String.t(),
          manifest: TwoRavens.Manifest.t(),
          files: %{String.t() => String.t()},
          before_files: %{String.t() => String.t()},
          operations: [map()],
          status: :ready | :needs_changes,
          diagnostics: [map()],
          qualification: map() | nil,
          expires_at: String.t()
        }

  @doc false
  @spec new(map()) :: t()
  def new(attributes) do
    now = DateTime.utc_now()

    struct!(
      __MODULE__,
      Map.merge(attributes, %{
        id: "draft:d_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
        version: 1,
        expires_at: now |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()
      })
    )
  end

  @doc false
  @spec next(t(), map()) :: t()
  def next(%__MODULE__{} = draft, attributes) do
    struct!(draft, Map.merge(attributes, %{version: draft.version + 1}))
  end

  @doc false
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = draft) do
    %{
      "id" => draft.id,
      "version" => draft.version,
      "base_revision" => draft.base_revision,
      "base_working_hash" => draft.base_working_hash,
      "base_hashes" => draft.base_hashes,
      "manifest_hash" => draft.manifest_hash,
      "manifest" => %{
        "schema_version" => draft.manifest.schema_version,
        "managed_paths" => draft.manifest.managed_paths
      },
      "files" => draft.files,
      "before_files" => draft.before_files,
      "operations" => draft.operations,
      "status" => Atom.to_string(draft.status),
      "diagnostics" => stringify(draft.diagnostics),
      "qualification" => stringify(draft.qualification),
      "expires_at" => draft.expires_at
    }
  end

  @doc false
  @spec load(map()) :: {:ok, t()} | {:error, map()}
  def load(payload) when is_map(payload) do
    with :ok <- exact_keys(payload, dump_keys()),
         {:ok, manifest} <- load_manifest(payload["manifest"]),
         {:ok, status} <- load_status(payload["status"]),
         :ok <- validate_loaded(payload),
         :ok <- validate_operations(payload["operations"]) do
      {:ok,
       %__MODULE__{
         id: payload["id"],
         version: payload["version"],
         base_revision: payload["base_revision"],
         base_working_hash: payload["base_working_hash"],
         base_hashes: payload["base_hashes"],
         manifest_hash: payload["manifest_hash"],
         manifest: manifest,
         files: payload["files"],
         before_files: payload["before_files"],
         operations: payload["operations"],
         status: status,
         diagnostics: payload["diagnostics"],
         qualification: payload["qualification"],
         expires_at: payload["expires_at"]
       }}
    end
  end

  def load(_payload), do: {:error, %{code: :draft_corrupt}}

  defp dump_keys do
    ~w(id version base_revision base_working_hash base_hashes manifest_hash manifest files before_files operations status diagnostics qualification expires_at)
  end

  defp validate_loaded(payload) do
    checks = [
      Enum.all?(
        ~w(id base_revision base_working_hash manifest_hash expires_at),
        &is_binary(payload[&1])
      ),
      is_integer(payload["version"]) and payload["version"] > 0,
      is_map(payload["base_hashes"]),
      valid_source_map?(payload["files"], true),
      valid_source_map?(payload["before_files"], false),
      is_list(payload["operations"]) and Enum.all?(payload["operations"], &is_map/1),
      is_list(payload["diagnostics"]),
      is_map(payload["qualification"]) or is_nil(payload["qualification"])
    ]

    if Enum.all?(checks), do: :ok, else: {:error, %{code: :draft_corrupt}}
  end

  defp valid_source_map?(value, allow_nil?) when is_map(value) do
    Enum.all?(Map.values(value), &(is_binary(&1) or (allow_nil? and is_nil(&1))))
  end

  defp valid_source_map?(_value, _allow_nil?), do: false

  defp load_manifest(%{"schema_version" => version, "managed_paths" => paths})
       when is_integer(version) and version > 0 and is_list(paths) do
    if Enum.all?(paths, &is_binary/1),
      do: {:ok, %TwoRavens.Manifest{schema_version: version, managed_paths: paths}},
      else: {:error, %{code: :draft_corrupt}}
  end

  defp load_manifest(_manifest), do: {:error, %{code: :draft_corrupt}}

  defp load_status("ready"), do: {:ok, :ready}
  defp load_status("needs_changes"), do: {:ok, :needs_changes}
  defp load_status(_status), do: {:error, %{code: :draft_corrupt}}

  defp validate_operations(operations) do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {operation, index}, :ok ->
      case Operation.validate(operation, index) do
        {:ok, _validated} -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, %{code: :draft_corrupt}}}
      end
    end)
  end

  defp exact_keys(map, expected) do
    if Map.keys(map) |> Enum.sort() == Enum.sort(expected),
      do: :ok,
      else: {:error, %{code: :draft_corrupt}}
  end

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_list(value), do: Enum.map(value, &stringify/1)

  defp stringify(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify(nested)} end)
  end

  defp stringify(value), do: value
end
