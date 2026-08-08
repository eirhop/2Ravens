defmodule TwoRavens.Materializer do
  @moduledoc "Atomic, revision-checked application of one qualified source candidate."

  alias TwoRavens.AtomicFile
  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Qualification.Evidence
  alias TwoRavens.Repository
  alias TwoRavens.SemanticStore
  alias TwoRavens.Source

  @doc "Applies a fully qualified candidate and restores original bytes on any returned failure."
  @spec apply(Candidate.t()) :: {:ok, Candidate.t()} | {:error, map()}
  def apply(%Candidate{evidence: %Evidence{profile: :apply}} = candidate) do
    with {:ok, project} <- Project.open(candidate.root),
         :ok <- verify_manifest_hash(project, candidate.manifest_hash),
         :ok <- verify_base_hashes(project, candidate.base_hashes),
         {:ok, snapshot} <- snapshot(project, Map.keys(candidate.files)) do
      apply_with_rollback(project, candidate, snapshot)
    end
  end

  def apply(%Candidate{}), do: {:error, %{code: :candidate_not_qualified}}

  defp apply_with_rollback(project, candidate, snapshot) do
    case SemanticStore.accept(project, candidate, fn -> commit_source(project, candidate) end) do
      {:ok, {accepted_graph, receipt}} ->
        evidence = %{candidate.evidence | accepted_graph: :pass}

        {:ok,
         %{
           candidate
           | graph: accepted_graph,
             evidence: evidence,
             applied: true,
             semantic: Map.put(candidate.semantic, :receipt, receipt)
         }}

      {:error, reason} ->
        case restore(project, snapshot) do
          :ok ->
            {:error, normalize_apply_error(reason)}

          {:error, rollback_reason} ->
            {:error, %{code: :rollback_failed, cause: reason, rollback: rollback_reason}}
        end
    end
  end

  defp commit_source(project, candidate) do
    with :ok <- write_files(project, candidate.files),
         :ok <- Manifest.write(project, candidate.manifest),
         {:ok, accepted_graph} <- Source.rebuild(project, candidate.manifest),
         :ok <- semantic_equal(accepted_graph, candidate.graph) do
      {:ok, accepted_graph}
    end
  end

  defp write_files(project, files) do
    files
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {path, source}, :ok ->
      with {:ok, absolute} <- Project.resolve(project, path),
           :ok <- write_file(absolute, source) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_file(path, nil) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, %{code: :source_delete_failed, path: path, reason: reason}}
    end
  end

  defp write_file(path, source), do: AtomicFile.write(path, source)

  defp semantic_equal(accepted_graph, proposed_graph) do
    if Graph.semantic_signature(accepted_graph) == Graph.semantic_signature(proposed_graph),
      do: :ok,
      else: {:error, %{code: :accepted_graph_mismatch}}
  end

  defp snapshot(project, paths) do
    with {:ok, manifest_path} <- Manifest.path(project),
         {:ok, manifest_content} <- File.read(manifest_path),
         {:ok, files} <- snapshot_files(project, paths) do
      {:ok, %{manifest: {manifest_path, manifest_content}, files: files}}
    else
      {:error, reason} -> {:error, %{code: :snapshot_failed, reason: reason}}
    end
  end

  defp snapshot_files(project, paths) do
    paths
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, snapshot} ->
      with {:ok, absolute} <- Project.resolve(project, path),
           {:ok, original} <- read_original(absolute) do
        {:cont, {:ok, Map.put(snapshot, path, original)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp read_original(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, {:present, source}}
      {:error, :enoent} -> {:ok, :missing}
      {:error, reason} -> {:error, %{code: :base_read_failed, path: path, reason: reason}}
    end
  end

  defp restore(project, snapshot) do
    results =
      Enum.map(snapshot.files, fn {path, original} -> restore_file(project, path, original) end) ++
        [restore_manifest(snapshot.manifest)]

    errors = Enum.reject(results, &(&1 == :ok))

    with [] <- errors,
         :ok <- verify_restored(project, snapshot) do
      :ok
    else
      [_first | _rest] = failures -> {:error, %{failures: failures}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_manifest({path, content}), do: AtomicFile.write(path, content)

  defp restore_file(project, path, {:present, content}) do
    with {:ok, absolute} <- Project.resolve(project, path) do
      AtomicFile.write(absolute, content)
    end
  end

  defp restore_file(project, path, :missing) do
    with {:ok, absolute} <- Project.resolve(project, path) do
      case File.rm(absolute) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp verify_restored(project, snapshot) do
    with :ok <- verify_content(snapshot.manifest) do
      verify_restored_files(project, snapshot.files)
    end
  end

  defp verify_restored_files(project, files) do
    Enum.reduce_while(files, :ok, fn {path, original}, :ok ->
      with {:ok, absolute} <- Project.resolve(project, path),
           :ok <- verify_original(absolute, original) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_content({path, expected}) do
    case File.read(path) do
      {:ok, ^expected} ->
        :ok

      {:ok, _changed} ->
        {:error, %{code: :rollback_verification_failed, path: path}}

      {:error, reason} ->
        {:error, %{code: :rollback_verification_failed, path: path, reason: reason}}
    end
  end

  defp verify_original(path, {:present, expected}), do: verify_content({path, expected})

  defp verify_original(path, :missing) do
    if File.exists?(path),
      do: {:error, %{code: :rollback_verification_failed, path: path}},
      else: :ok
  end

  defp verify_manifest_hash(project, expected) do
    case Manifest.content_hash(project) do
      {:ok, ^expected} -> :ok
      {:ok, _changed} -> {:error, %{code: :stale_manifest}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_base_hashes(project, base_hashes) do
    Enum.reduce_while(base_hashes, :ok, fn {path, expected}, :ok ->
      with {:ok, absolute} <- Project.resolve(project, path),
           :ok <- verify_base_hash(absolute, path, expected) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_base_hash(absolute, path, expected) do
    case current_hash(absolute) do
      {:ok, ^expected} -> :ok
      {:error, reason} -> {:error, %{code: :base_read_failed, path: path, reason: reason}}
      {:ok, _changed} -> {:error, %{code: :stale_source, path: path}}
    end
  end

  defp current_hash(absolute) do
    case File.read(absolute) do
      {:ok, source} -> {:ok, Repository.hash(source)}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_apply_error(%{code: :accepted_graph_mismatch} = reason), do: reason
  defp normalize_apply_error(reason), do: %{code: :apply_failed, reason: reason}
end
