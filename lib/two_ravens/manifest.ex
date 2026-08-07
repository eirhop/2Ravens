defmodule TwoRavens.Manifest do
  @moduledoc "Small versioned management metadata granting write authority."

  alias TwoRavens.AtomicFile
  alias TwoRavens.Project
  alias TwoRavens.Repository

  @schema_version 1
  @relative_path ".ravens/manifest"

  @enforce_keys [:schema_version, :managed_paths]
  defstruct [:schema_version, :managed_paths]

  @type t :: %__MODULE__{schema_version: pos_integer(), managed_paths: [String.t()]}

  @doc "Initializes the manifest without modifying existing source."
  @spec init(Project.t()) :: {:ok, t()} | {:error, map()}
  def init(%Project{} = project) do
    with {:ok, path} <- path(project) do
      if File.exists?(path) do
        load(project)
      else
        create(path)
      end
    end
  end

  @doc "Loads and strictly validates the management manifest."
  @spec load(Project.t()) :: {:ok, t()} | {:error, map()}
  def load(%Project{} = project) do
    with {:ok, path} <- path(project) do
      load_path(path)
    end
  end

  @doc "Adds one validated path deterministically."
  @spec add(t(), String.t()) :: {:ok, t()} | {:error, map()}
  def add(%__MODULE__{} = manifest, relative_path) do
    with {:ok, normalized} <- Project.managed_path(relative_path) do
      {:ok,
       %{manifest | managed_paths: Enum.sort(Enum.uniq([normalized | manifest.managed_paths]))}}
    end
  end

  @doc "Persists a validated manifest atomically."
  @spec write(Project.t(), t()) :: :ok | {:error, map()}
  def write(%Project{} = project, %__MODULE__{} = manifest) do
    with :ok <- validate_paths(manifest.managed_paths),
         {:ok, path} <- path(project),
         :ok <- AtomicFile.write(path, encode(manifest)) do
      :ok
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
      {:error, reason} -> {:error, %{code: :manifest_write_failed, reason: reason}}
    end
  end

  @doc "Returns the current manifest content hash."
  @spec content_hash(Project.t()) :: {:ok, String.t()} | {:error, map()}
  def content_hash(%Project{} = project) do
    with {:ok, path} <- path(project) do
      case File.read(path) do
        {:ok, content} -> {:ok, Repository.hash(content)}
        {:error, reason} -> {:error, %{code: :manifest_read_failed, reason: reason}}
      end
    end
  end

  @doc "Returns the manifest's absolute path."
  @spec path(Project.t()) :: {:ok, String.t()} | {:error, map()}
  def path(%Project{} = project), do: Project.resolve_internal(project, @relative_path)

  @doc false
  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{schema_version: version, managed_paths: paths}) do
    (["schema_version=#{version}"] ++ Enum.map(Enum.sort(paths), &"managed_path=#{&1}"))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp create(path) do
    manifest = %__MODULE__{schema_version: @schema_version, managed_paths: []}

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- AtomicFile.write(path, encode(manifest)) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, %{code: :manifest_write_failed, reason: reason}}
    end
  end

  defp load_path(path) do
    with {:ok, content} <- File.read(path),
         {:ok, manifest} <- decode(content),
         :ok <- validate_paths(manifest.managed_paths) do
      {:ok, manifest}
    else
      {:error, :enoent} -> {:error, %{code: :missing_manifest, path: path}}
      {:error, %{code: _code} = reason} -> {:error, reason}
      {:error, reason} -> {:error, %{code: :manifest_read_failed, reason: reason}}
    end
  end

  defp decode(content) do
    lines = String.split(content, ~r/\R/, trim: true)

    with ["schema_version=" <> version | path_lines] <- lines,
         {version, ""} <- Integer.parse(version),
         true <- version == @schema_version,
         true <- Enum.all?(path_lines, &String.starts_with?(&1, "managed_path=")) do
      paths = Enum.map(path_lines, &String.replace_prefix(&1, "managed_path=", ""))

      if paths == Enum.sort(Enum.uniq(paths)) do
        {:ok, %__MODULE__{schema_version: version, managed_paths: paths}}
      else
        {:error, %{code: :corrupt_manifest, reason: :unordered_or_duplicate_paths}}
      end
    else
      false -> {:error, %{code: :unsupported_manifest}}
      _ -> {:error, %{code: :corrupt_manifest}}
    end
  end

  defp validate_paths(paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case Project.managed_path(path) do
        {:ok, ^path} -> {:cont, :ok}
        _ -> {:halt, {:error, %{code: :invalid_managed_path, value: path}}}
      end
    end)
  end
end
