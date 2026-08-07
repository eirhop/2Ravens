defmodule TwoRavens.Context do
  @moduledoc "The narrow, function-focused context query for managed greenfield source."

  alias TwoRavens.Authoring.Options
  alias TwoRavens.Context.Result
  alias TwoRavens.EditHandle
  alias TwoRavens.Graph
  alias TwoRavens.Project
  alias TwoRavens.Source

  @doc """
  Returns compact context for one canonical function focus.

  The MVP accepts only `function:Module.name/arity`. Its graph is rebuilt from
  managed files on every call; broader Phase 1 focus and traversal forms return
  an explicit error.
  """
  @spec query(Path.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, map()}
  def query(root, focus, options \\ [])

  def query(root, focus, options) when is_binary(root) and is_binary(focus) do
    with :ok <- validate_options(options),
         {:ok, project} <- Project.open(root),
         {:ok, graph} <- Source.rebuild(project.root),
         {:ok, function} <- Graph.function(graph, focus),
         {:ok, fragment} <- fragment_for(graph, function.source.path),
         {:ok, absolute} <- Project.resolve(project, function.source.path),
         {:ok, source} <- File.read(absolute) do
      file_hash = Map.fetch!(graph.revision.file_hashes, function.source.path)

      editable_comparisons =
        function.clauses
        |> Enum.flat_map(& &1.comparisons)
        |> Enum.map(fn comparison ->
          %{
            handle: EditHandle.encode(file_hash, comparison),
            property: "operator",
            value: comparison.operator,
            comparison: comparison
          }
        end)

      {:ok,
       %Result{
         focus: focus,
         function: function,
         clauses: function.clauses,
         callers: Graph.callers(graph, focus),
         upstream: Graph.upstream(graph, focus),
         callees: Graph.callees(graph, focus),
         tests: Graph.related_tests(graph, focus),
         editable_comparisons: editable_comparisons,
         freshness: %{
           revision: graph.revision.working_hash,
           git_revision: graph.revision.git_revision,
           file_hash: file_hash,
           status: :current,
           indexed_files: map_size(graph.fragments),
           scope: :managed_files_only
         },
         unsupported: Enum.sort(Enum.uniq(fragment.unsupported ++ graph.unsupported)),
         frontier: ["unmanaged repository source is outside the MVP index"],
         source: Source.select(source, function.source)
       }}
    else
      {:error, :enoent} -> {:error, %{code: :managed_file_read_failed}}
      {:error, reason} -> {:error, reason}
    end
  end

  def query(root, focus, _options),
    do: {:error, %{code: :invalid_arguments, arguments: %{root: root, focus: focus}}}

  defp validate_options(options) do
    case Options.validate(options, for_edit: {:boolean, false}) do
      {:ok, _options} ->
        :ok

      {:error, %{code: :unsupported_options, options: unsupported}} ->
        {:error, %{code: :unsupported_query_options, options: unsupported}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fragment_for(graph, path) do
    case graph.fragments do
      %{^path => fragment} -> {:ok, fragment}
      _ -> {:error, %{code: :managed_fragment_not_found, path: path}}
    end
  end
end
