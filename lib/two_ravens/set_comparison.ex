defmodule TwoRavens.SetComparison do
  @moduledoc false

  alias TwoRavens.Authoring.BoundaryImpact
  alias TwoRavens.Authoring.BoundaryTestEvidence
  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Authoring.Support
  alias TwoRavens.Diff
  alias TwoRavens.EditHandle
  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Source
  alias TwoRavens.Source.Comparison
  alias TwoRavens.Source.Function

  @operators ["==", "!=", "===", "!==", "<", "<=", ">", ">="]

  @spec build(Path.t(), String.t(), String.t()) :: {:ok, Proposal.t()} | {:error, map()}
  def build(root, target, operator) do
    with :ok <- validate_operator(operator),
         {:ok, handle} <- decode_target(target),
         {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         {:ok, manifest_hash} <- Manifest.content_hash(project),
         :ok <- ensure_managed(manifest, handle.path),
         {:ok, graph} <- Source.rebuild(project, manifest),
         :ok <- Support.reject_path_unsupported(graph, handle.path),
         :ok <- current_handle_hash(graph, handle),
         {:ok, comparison} <- resolve_comparison(graph, handle),
         {:ok, before} <- Support.read_source(project, handle.path),
         {:ok, source} <- replace_operator(before, comparison, operator),
         {:ok, proposed_graph} <- Source.rebuild_with(project, manifest, %{handle.path => source}),
         :ok <- validate_delta(graph, proposed_graph, comparison, operator, before, source) do
      {:ok,
       %Proposal{
         kind: :set,
         project: project,
         files: %{handle.path => source},
         before_files: %{handle.path => before},
         base_hashes: %{handle.path => handle.file_hash},
         manifest: manifest,
         manifest_hash: manifest_hash,
         graph: proposed_graph,
         details: details(project, graph, comparison, operator, before, source)
       }}
    end
  end

  defp replace_operator(source, comparison, operator) do
    line_index = comparison.source.start_line - 1
    column_index = comparison.source.start_column - 1
    lines = String.split(source, "\n", trim: false)
    line = Enum.at(lines, line_index)

    cond do
      is_nil(line) ->
        {:error, %{code: :stale_handle}}

      String.slice(line, column_index, String.length(comparison.operator)) != comparison.operator ->
        {:error, %{code: :stale_handle}}

      true ->
        changed =
          String.slice(line, 0, column_index) <>
            operator <>
            String.slice(line, (column_index + String.length(comparison.operator))..-1//1)

        {:ok, lines |> List.replace_at(line_index, changed) |> Enum.join("\n")}
    end
  end

  defp validate_delta(before_graph, changed_graph, comparison, operator, before, changed_source) do
    matching =
      changed_graph.nodes
      |> Map.values()
      |> Enum.filter(fn
        %Comparison{} = candidate ->
          candidate.function_id == comparison.function_id and
            candidate.left == comparison.left and candidate.right == comparison.right and
            candidate.operator == operator and
            candidate.source.start_line == comparison.source.start_line

        _other ->
          false
      end)

    with :ok <- one_changed_line(before, changed_source),
         :ok <- one_matching_comparison(matching),
         :ok <- same_node_count(before_graph, changed_graph) do
      same_stable_edges(before_graph, changed_graph)
    end
  end

  defp one_changed_line(before, changed_source) do
    if Diff.changed_lines(before, changed_source) == 1,
      do: :ok,
      else: {:error, %{code: :unrelated_source_change}}
  end

  defp one_matching_comparison([_comparison]), do: :ok

  defp one_matching_comparison(_comparisons),
    do: {:error, %{code: :graph_round_trip_mismatch, reason: :edited_comparison_missing}}

  defp same_node_count(before_graph, changed_graph) do
    if map_size(before_graph.nodes) == map_size(changed_graph.nodes),
      do: :ok,
      else: {:error, %{code: :unrelated_graph_change}}
  end

  defp same_stable_edges(before_graph, changed_graph) do
    if stable_edges(before_graph) == stable_edges(changed_graph),
      do: :ok,
      else: {:error, %{code: :unrelated_graph_change}}
  end

  defp stable_edges(graph) do
    graph.edges
    |> Enum.reject(&(&1.kind == :defines))
    |> Enum.map(&{&1.kind, &1.from, &1.to})
  end

  defp details(project, graph, comparison, operator, before, source) do
    related_tests = Graph.related_tests(graph, comparison.function_id)

    %{
      path: comparison.source.path,
      target: comparison.id,
      from: comparison.operator,
      to: operator,
      direct_impact: comparison.function_id,
      upstream: Graph.upstream(graph, comparison.function_id),
      tests: related_tests,
      boundary:
        BoundaryImpact.analyze(comparison, operator, %{
          fallback: fallback_evidence(graph, comparison),
          test_evidence:
            BoundaryTestEvidence.analyze(
              project,
              graph,
              related_tests,
              comparison
            )
        }),
      changed_lines: Diff.changed_lines(before, source)
    }
  end

  defp fallback_evidence(graph, comparison) do
    with %Function{} = function <- Map.get(graph.nodes, comparison.function_id),
         current_index when not is_nil(current_index) <-
           Enum.find_index(function.clauses, &(&1.id == comparison.clause_id)),
         current when not is_nil(current) <- Enum.at(function.clauses, current_index),
         fallback when not is_nil(fallback) <- Enum.at(function.clauses, current_index + 1),
         true <- fallback.patterns == current.patterns,
         :matches <- guard_at_boundary(fallback, comparison) do
      %{status: :confirmed, reason: :same_patterns_and_true_guard, clause: fallback.id}
    else
      _ -> %{status: :unknown, reason: :clause_compatibility_not_derived}
    end
  end

  defp guard_at_boundary(%{guard: nil}, _comparison), do: :matches

  defp guard_at_boundary(%{comparisons: [guard]}, comparison) do
    with true <- guard.left == comparison.left,
         {:ok, boundary} <- parse_integer(comparison.right),
         {:ok, threshold} <- parse_integer(guard.right) do
      compare(boundary, guard.operator, threshold)
    else
      _ -> :unknown
    end
  end

  defp guard_at_boundary(_clause, _comparison), do: :unknown

  defp compare(left, "==", right), do: truth(left == right)
  defp compare(left, "!=", right), do: truth(left != right)
  defp compare(left, "===", right), do: truth(left === right)
  defp compare(left, "!==", right), do: truth(left !== right)
  defp compare(left, "<", right), do: truth(left < right)
  defp compare(left, "<=", right), do: truth(left <= right)
  defp compare(left, ">", right), do: truth(left > right)
  defp compare(left, ">=", right), do: truth(left >= right)
  defp compare(_left, _operator, _right), do: :unknown

  defp truth(true), do: :matches
  defp truth(false), do: :does_not_match

  defp parse_integer(value) do
    case value |> String.replace("_", "") |> Integer.parse() do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp resolve_comparison(graph, handle) do
    matches =
      graph.nodes
      |> Map.values()
      |> Enum.filter(fn
        %Comparison{} = comparison ->
          comparison.source.path == handle.path and
            comparison.function_id == handle.function_id and
            comparison.clause_fingerprint == handle.clause_fingerprint and
            comparison.fingerprint == handle.expression_fingerprint

        _other ->
          false
      end)

    case matches do
      [comparison] -> {:ok, comparison}
      [] -> {:error, %{code: :stale_handle}}
      _many -> {:error, %{code: :ambiguous_target}}
    end
  end

  defp current_handle_hash(graph, handle) do
    path = handle.path
    file_hash = handle.file_hash

    case graph.revision.file_hashes do
      %{^path => ^file_hash} -> :ok
      _ -> {:error, %{code: :stale_handle}}
    end
  end

  defp ensure_managed(manifest, path) do
    if path in manifest.managed_paths,
      do: :ok,
      else: {:error, %{code: :unmanaged_path, path: path}}
  end

  defp decode_target(target) do
    handle = String.replace_suffix(target, ".operator", "")

    if handle == target do
      {:error, %{code: :invalid_property, supported: "operator"}}
    else
      EditHandle.decode(handle)
    end
  end

  defp validate_operator(operator) when operator in @operators, do: :ok
  defp validate_operator(operator), do: {:error, %{code: :unsupported_operator, value: operator}}
end
