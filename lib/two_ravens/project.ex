defmodule TwoRavens.Project do
  @moduledoc "Safe discovery of an ordinary Mix project and managed paths."

  alias TwoRavens.ManagedPath

  @enforce_keys [:root]
  defstruct [:root]

  @type t :: %__MODULE__{root: String.t()}

  @doc "Validates and resolves an existing, non-broad Mix project root."
  @spec open(Path.t()) :: {:ok, t()} | {:error, map()}
  def open(path) when is_binary(path) do
    root = Path.expand(path)

    cond do
      not File.dir?(root) -> error(:missing_project, root)
      broad_path?(root) -> error(:unsafe_root, root)
      not File.regular?(Path.join(root, "mix.exs")) -> error(:not_mix_project, root)
      true -> {:ok, %__MODULE__{root: root}}
    end
  end

  def open(path), do: error(:invalid_project_path, path)

  @doc "Resolves a validated managed relative path beneath the project root."
  @spec resolve(t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  def resolve(%__MODULE__{root: root}, relative_path) do
    with {:ok, managed_path} <- ManagedPath.new(relative_path),
         relative <- ManagedPath.relative(managed_path),
         absolute <- Path.join(root, relative),
         :ok <- reject_linked_components(root, relative) do
      {:ok, absolute}
    end
  end

  @doc "Resolves a fixed repository-internal metadata path without following links."
  @spec resolve_internal(t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  def resolve_internal(%__MODULE__{root: root}, relative_path) when is_binary(relative_path) do
    normalized = String.replace(relative_path, "\\", "/")
    segments = Path.split(normalized)

    cond do
      relative_path == "" or String.contains?(relative_path, <<0>>) ->
        error(:invalid_internal_path, relative_path)

      Path.type(normalized) != :relative or Enum.any?(segments, &(&1 in [".", "..", ""])) ->
        error(:invalid_internal_path, relative_path)

      true ->
        relative = Enum.join(segments, "/")

        with :ok <- reject_linked_components(root, relative) do
          {:ok, Path.join(root, relative)}
        end
    end
  end

  def resolve_internal(%__MODULE__{}, relative_path),
    do: error(:invalid_internal_path, relative_path)

  @doc "Normalizes a repository-relative managed path without touching the filesystem."
  @spec managed_path(String.t()) :: {:ok, String.t()} | {:error, map()}
  def managed_path(path) do
    with {:ok, managed_path} <- ManagedPath.new(path) do
      {:ok, ManagedPath.relative(managed_path)}
    end
  end

  @doc "Infers the conventional path for a validated module name."
  @spec module_path(String.t(), boolean()) :: {:ok, String.t()} | {:error, map()}
  def module_path(module, test?) when is_binary(module) and is_boolean(test?) do
    with :ok <- validate_module_name(module) do
      underscored = Macro.underscore(module)

      path =
        if test? do
          base = String.replace_suffix(underscored, "_test", "")
          "test/#{base}_test.exs"
        else
          "lib/#{underscored}.ex"
        end

      {:ok, path}
    end
  end

  def module_path(module, test?),
    do: {:error, %{code: :invalid_arguments, arguments: %{module: module, test: test?}}}

  @doc "Validates an Elixir alias string without converting it to atoms."
  @spec validate_module_name(String.t()) :: :ok | {:error, map()}
  def validate_module_name(module) when is_binary(module) do
    valid_segments? =
      module
      |> String.split(".")
      |> Enum.all?(&(byte_size(&1) <= 64))

    if byte_size(module) <= 255 and valid_segments? and
         Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*$/, module) do
      :ok
    else
      error(:invalid_module_name, module)
    end
  end

  def validate_module_name(module), do: error(:invalid_module_name, module)

  defp broad_path?(root) do
    parent = Path.dirname(root)
    home = System.user_home!() |> Path.expand()
    same_path?(root, parent) or same_path?(root, home)
  end

  defp reject_linked_components(root, relative) do
    relative
    |> Path.split()
    |> Enum.scan(root, &Path.join(&2, &1))
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} ->
          {:halt, {:error, %{code: :unsafe_managed_path, path: path, reason: :symbolic_link}}}

        {:ok, _stat} ->
          {:cont, :ok}

        {:error, :enoent} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, %{code: :managed_path_inspection_failed, path: path, reason: reason}}}
      end
    end)
  end

  defp same_path?(left, right),
    do: String.downcase(Path.expand(left)) == String.downcase(Path.expand(right))

  defp error(code, value), do: {:error, %{code: code, value: value}}
end
