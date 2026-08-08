defmodule TwoRavens.Context do
  @moduledoc "Persisted function context with freshness-checked source opt-in."

  alias TwoRavens.Authoring.Options
  alias TwoRavens.Authoring.Support
  alias TwoRavens.Context.Result
  alias TwoRavens.EditHandle
  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Selection
  alias TwoRavens.Selector
  alias TwoRavens.SemanticStore
  alias TwoRavens.Source

  @includes [:intent, :callers, :callees, :tests, :evidence, :source, :clauses, :editable]

  @doc "Returns compact persisted context for one canonical function focus."
  @spec query(Path.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, map()}
  def query(root, focus, options \\ [])

  def query(root, focus, options) when is_binary(root) and is_binary(focus) do
    with {:ok, options} <- validate_options(options),
         {:ok, memory} <- SemanticStore.context(root, focus) do
      result = persisted_result(focus, memory, options)
      maybe_materialize_source(root, memory, result, options)
    end
  end

  def query(root, focus, _options),
    do: {:error, %{code: :invalid_arguments, arguments: %{root: root, focus: focus}}}

  @doc "Returns several bounded semantic selections from one exact managed-source revision."
  @spec batch(Path.t(), map()) :: {:ok, map()} | {:error, map()}
  def batch(root, %{"select" => selectors} = request)
      when is_binary(root) and map_size(request) == 1 do
    with {:ok, selectors} <- Selector.validate(selectors),
         {:ok, freshness} <- SemanticStore.synchronize(root),
         {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         {:ok, graph} <- Source.rebuild(project, manifest),
         :ok <- ensure_same_revision(graph, freshness.revision.working_hash),
         {:ok, files} <- load_files(project, manifest),
         {:ok, results} <- Selection.resolve(graph, files, selectors) do
      {:ok,
       %{
         base_revision: freshness.revision.id,
         freshness: Map.drop(freshness, [:revision]),
         results: results,
         truncated: Enum.any?(results, &Map.get(&1, :truncated, false))
       }}
    end
  end

  def batch(_root, _request),
    do: {:error, %{code: :invalid_arguments, reason: :exact_select_field_required}}

  defp validate_options(options) do
    case Options.validate(options,
           for_edit: {:boolean, false},
           include: {:binary_list, []},
           compact: {:boolean, true},
           details: {:boolean, false}
         ) do
      {:ok, options} ->
        normalize_query_options(options)

      {:error, %{code: :unsupported_options, options: unsupported}} ->
        {:error, %{code: :unsupported_query_options, options: unsupported}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_query_options(options) do
    with {:ok, includes} <- normalize_includes(options.include) do
      {:ok, %{options | include: included_fields(options, includes)}}
    end
  end

  defp included_fields(%{details: true}, _includes), do: @includes

  defp included_fields(%{for_edit: true}, includes),
    do: Enum.uniq([:source, :clauses, :editable, :callers, :tests | includes])

  defp included_fields(_options, includes), do: includes

  defp normalize_includes(includes) do
    values =
      includes
      |> Enum.flat_map(&String.split(&1, ",", trim: true))
      |> Enum.map(&String.trim/1)

    unknown = Enum.reject(values, &(include_atom(&1) in @includes))

    if unknown == [] do
      {:ok, values |> Enum.map(&include_atom/1) |> Enum.uniq()}
    else
      {:error, %{code: :unsupported_includes, includes: Enum.sort(unknown)}}
    end
  end

  defp include_atom("intent"), do: :intent
  defp include_atom("callers"), do: :callers
  defp include_atom("callees"), do: :callees
  defp include_atom("tests"), do: :tests
  defp include_atom("evidence"), do: :evidence
  defp include_atom("source"), do: :source
  defp include_atom("clauses"), do: :clauses
  defp include_atom("editable"), do: :editable
  defp include_atom(_unknown), do: nil

  defp persisted_result(focus, memory, options) do
    include = options.include

    %Result{
      focus: focus,
      entity: memory.entity,
      include: include,
      callers: selected(include, :callers, semantic_keys(memory.callers)),
      caller_relations: selected(include, :callers, memory.callers),
      callees: selected(include, :callees, semantic_keys(memory.callees)),
      callee_relations: selected(include, :callees, memory.callees),
      tests:
        selected(include, :tests, Enum.map(memory.derived_tests, &test_module(&1.semantic_key))),
      derived_test_relations: selected(include, :tests, memory.derived_tests),
      requested_tests: selected(include, :tests, memory.requested_tests),
      intents: selected(include, :intent, memory.intents),
      evidence: selected(include, :evidence, memory.evidence),
      freshness: freshness(memory),
      frontier:
        Enum.uniq(memory.frontier ++ ["unmanaged repository source is outside the MVP index"])
    }
  end

  defp freshness(memory) do
    %{
      status: memory.freshness.status,
      revision: memory.revision.working_hash,
      semantic_revision: memory.revision.id,
      git_revision: memory.revision.git_revision,
      intent_status: memory.revision.intent_status,
      intent_reason: memory.revision.reason,
      graph_rebuilt: memory.freshness.graph_rebuilt,
      scope: :managed_files_only
    }
  end

  defp selected(include, field, value), do: if(field in include, do: value, else: [])

  defp maybe_materialize_source(root, memory, result, options) do
    if options.for_edit or Enum.any?([:source, :clauses, :editable], &(&1 in options.include)) do
      source_result(root, memory, result)
    else
      {:ok, result}
    end
  end

  defp source_result(root, memory, result) do
    with {:ok, project} <- Project.open(root),
         {:ok, graph} <- Source.rebuild(project.root),
         :ok <- ensure_same_revision(graph, memory.revision.working_hash),
         {:ok, function} <- Graph.function(graph, result.focus),
         {:ok, fragment} <- fragment_for(graph, function.source.path),
         {:ok, absolute} <- Project.resolve(project, function.source.path),
         {:ok, source} <- File.read(absolute) do
      file_hash = Map.fetch!(graph.revision.file_hashes, function.source.path)

      editables = editable_comparisons(function, file_hash, result.include)

      {:ok,
       %{
         result
         | function: function,
           clauses: selected(result.include, :clauses, function.clauses),
           upstream: selected(result.include, :callers, Graph.upstream(graph, result.focus)),
           editable_comparisons: editables,
           unsupported: Enum.sort(Enum.uniq(fragment.unsupported ++ graph.unsupported)),
           source: selected_source(result.include, source, function.source),
           freshness: Map.put(result.freshness, :file_hash, file_hash)
       }}
    else
      {:error, :enoent} -> {:error, %{code: :managed_file_read_failed}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp editable_comparisons(function, file_hash, include) do
    comparisons =
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

    selected(include, :editable, comparisons)
  end

  defp selected_source(include, source, range) do
    if :source in include, do: Source.select(source, range), else: nil
  end

  defp ensure_same_revision(%{revision: %{working_hash: hash}}, hash), do: :ok
  defp ensure_same_revision(_graph, _expected), do: {:error, %{code: :stale_source_during_query}}

  defp semantic_keys(relations), do: Enum.map(relations, & &1.semantic_key)

  defp test_module("test:" <> rest) do
    rest |> String.split(":") |> List.first()
  end

  defp test_module(semantic_key), do: semantic_key

  defp fragment_for(graph, path) do
    case graph.fragments do
      %{^path => fragment} -> {:ok, fragment}
      _ -> {:error, %{code: :managed_fragment_not_found, path: path}}
    end
  end

  defp load_files(project, manifest) do
    Enum.reduce_while(manifest.managed_paths, {:ok, %{}}, fn path, {:ok, files} ->
      case Support.read_source(project, path) do
        {:ok, source} -> {:cont, {:ok, Map.put(files, path, source)}}
        error -> {:halt, error}
      end
    end)
  end
end
