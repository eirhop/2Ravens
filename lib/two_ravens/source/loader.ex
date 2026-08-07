defmodule TwoRavens.Source.Loader do
  @moduledoc false

  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Repository
  alias TwoRavens.Source.Parser

  @spec rebuild(Path.t()) :: {:ok, Graph.t()} | {:error, map()}
  def rebuild(root) when is_binary(root) do
    with {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project) do
      rebuild(project, manifest)
    end
  end

  def rebuild(root), do: {:error, %{code: :invalid_argument, argument: :root, value: root}}

  @spec rebuild(Project.t(), Manifest.t()) :: {:ok, Graph.t()} | {:error, map()}
  def rebuild(%Project{} = project, %Manifest{} = manifest) do
    rebuild_with(project, manifest, %{})
  end

  @spec rebuild_with(Project.t(), Manifest.t(), %{String.t() => String.t()}) ::
          {:ok, Graph.t()} | {:error, map()}
  def rebuild_with(%Project{} = project, %Manifest{} = manifest, candidate_files)
      when is_map(candidate_files) do
    result =
      Enum.reduce_while(manifest.managed_paths, {:ok, [], %{}}, fn path,
                                                                   {:ok, fragments, hashes} ->
        with {:ok, absolute} <- Project.resolve(project, path),
             {:ok, source} <- candidate_source(candidate_files, absolute, path),
             {:ok, fragment} <- Parser.parse(path, source) do
          {:cont, {:ok, [fragment | fragments], Map.put(hashes, path, Repository.hash(source))}}
        else
          {:error, %{code: :missing_managed_file}} ->
            {:halt, {:error, %{code: :missing_managed_file, path: path, freshness: :missing}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    with {:ok, fragments, hashes} <- result do
      revision = Repository.revision(project.root, hashes)
      Graph.build(Enum.reverse(fragments), revision)
    end
  end

  defp candidate_source(candidate_files, absolute, path) do
    case candidate_files do
      %{^path => source} when is_binary(source) ->
        {:ok, source}

      %{^path => source} ->
        {:error, %{code: :invalid_candidate_source, path: path, value: source}}

      _ ->
        read_managed(absolute, path)
    end
  end

  defp read_managed(absolute, path) do
    case File.read(absolute) do
      {:ok, source} -> {:ok, source}
      {:error, :enoent} -> {:error, %{code: :missing_managed_file, path: path}}
      {:error, reason} -> {:error, %{code: :managed_file_read_failed, path: path, reason: reason}}
    end
  end
end
