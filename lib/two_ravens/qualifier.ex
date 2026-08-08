defmodule TwoRavens.Qualifier do
  @moduledoc "Isolated formatting, graph round-trip, compilation, and test qualification."

  alias TwoRavens.AtomicFile
  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Qualification.Evidence
  alias TwoRavens.Qualifier.Result
  alias TwoRavens.Source

  @doc "Qualifies candidate files inside a disposable copy of the target project."
  @spec qualify(
          Project.t(),
          Manifest.t(),
          %{String.t() => String.t()},
          Graph.t(),
          :qualified_dry_run | :apply
        ) ::
          {:ok, Result.t()} | {:error, map()}
  def qualify(%Project{} = project, %Manifest{} = manifest, files, proposed_graph, profile) do
    temporary_root =
      Path.join(
        System.tmp_dir!(),
        "two-ravens-qualify-#{System.unique_integer([:positive, :monotonic])}"
      )

    candidate_root = Path.join(temporary_root, "project")

    try do
      with :ok <- File.mkdir_p(temporary_root),
           {:ok, _copied} <- File.cp_r(project.root, candidate_root),
           :ok <- remove_build_artifacts(candidate_root),
           {:ok, candidate_project} <- Project.open(candidate_root),
           :ok <- materialize(candidate_project, files),
           :ok <- Manifest.write(candidate_project, manifest),
           {:ok, before_format_graph} <- Source.rebuild(candidate_project, manifest),
           :ok <- semantic_equal(before_format_graph, proposed_graph, :materialize),
           paths <-
             files
             |> Enum.reject(fn {_path, source} -> is_nil(source) end)
             |> Enum.map(&elem(&1, 0))
             |> Enum.sort(),
           {:ok, format_output} <- run_mix(candidate_root, ["format" | paths]),
           {:ok, formatted_files} <- read_files(candidate_project, paths),
           {:ok, formatted_graph} <- Source.rebuild(candidate_project, manifest),
           :ok <- semantic_equal(formatted_graph, proposed_graph, :format),
           {:ok, verification_output} <-
             run_mix(
               candidate_root,
               [
                 "do",
                 "compile",
                 "--warnings-as-errors",
                 ",",
                 "test",
                 "--no-compile"
               ],
               [{"MIX_ENV", "test"}]
             ) do
        output_bytes = byte_size(format_output) + byte_size(verification_output)

        {:ok,
         %Result{
           files:
             Map.merge(
               Map.filter(files, fn {_path, source} -> is_nil(source) end),
               formatted_files
             ),
           graph: formatted_graph,
           evidence: Evidence.qualified(profile, output_bytes, 2)
         }}
      else
        {:error, reason, path} ->
          {:error, %{code: :qualification_copy_failed, reason: reason, path: path}}

        {:error, reason} ->
          {:error, normalize_error(reason)}
      end
    after
      File.rm_rf(temporary_root)
    end
  end

  defp materialize(project, files) do
    Enum.reduce_while(files, :ok, fn {relative, source}, :ok ->
      with {:ok, absolute} <- Project.resolve(project, relative),
           :ok <- materialize_file(absolute, source) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp materialize_file(path, nil) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, %{code: :qualification_delete_failed, path: path, reason: reason}}
    end
  end

  defp materialize_file(path, source), do: AtomicFile.write(path, source)

  defp read_files(project, paths) do
    Enum.reduce_while(paths, {:ok, %{}}, fn path, {:ok, files} ->
      with {:ok, absolute} <- Project.resolve(project, path),
           {:ok, source} <- File.read(absolute) do
        {:cont, {:ok, Map.put(files, path, source)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp remove_build_artifacts(root) do
    Enum.reduce_while(["_build", "deps", ".git"], :ok, fn path, :ok ->
      case File.rm_rf(Path.join(root, path)) do
        {:ok, _removed} ->
          {:cont, :ok}

        {:error, reason, failed_path} ->
          {:halt,
           {:error, %{code: :qualification_cleanup_failed, path: failed_path, reason: reason}}}
      end
    end)
  end

  defp semantic_equal(left, right, stage) do
    if Graph.semantic_signature(left) == Graph.semantic_signature(right) do
      :ok
    else
      {:error, %{code: :graph_round_trip_mismatch, stage: stage}}
    end
  end

  defp run_mix(root, arguments, environment \\ []) do
    executable = System.find_executable("mix") || "mix"

    case System.cmd(executable, arguments,
           cd: root,
           env: environment,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, output}

      {output, status} ->
        {:error,
         %{
           code: :qualification_failed,
           command: Enum.join(["mix" | arguments], " "),
           status: status,
           diagnostic: diagnostic(output)
         }}
    end
  end

  defp diagnostic(output) do
    output
    |> String.split("\n")
    |> Enum.take(-30)
    |> Enum.join("\n")
  end

  defp normalize_error(%{code: _code} = reason), do: reason
  defp normalize_error(reason), do: %{code: :qualification_failed, reason: inspect(reason)}
end
