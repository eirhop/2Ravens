defmodule TwoRavens.Graph do
  @moduledoc "Deterministic graph construction and bounded MVP traversal."

  @enforce_keys [:revision, :fragments, :nodes, :edges, :unsupported]
  defstruct [:revision, :fragments, :nodes, :edges, :unsupported]

  @type t :: %__MODULE__{
          revision: TwoRavens.Repository.Revision.t(),
          fragments: %{String.t() => TwoRavens.Source.Fragment.t()},
          nodes: %{String.t() => struct()},
          edges: [TwoRavens.Graph.Edge.t()],
          unsupported: [String.t()]
        }

  alias TwoRavens.Evidence
  alias TwoRavens.Graph.Edge
  alias TwoRavens.Identity
  alias TwoRavens.Repository.Revision
  alias TwoRavens.Source.Fragment
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Module
  alias TwoRavens.Source.Test

  @doc "Builds nodes and derived edges from deterministic file fragments."
  @spec build([Fragment.t()], Revision.t()) :: {:ok, t()} | {:error, map()}
  def build(fragments, revision) do
    fragments = Enum.sort_by(fragments, & &1.path)

    with {:ok, nodes} <- build_nodes(fragments) do
      fragment_map = Map.new(fragments, &{&1.path, &1})
      edges = build_edges(fragments, nodes)
      unsupported = fragment_unsupported(fragments) ++ unresolved_call_facts(fragments, nodes)

      {:ok,
       %__MODULE__{
         revision: revision,
         fragments: fragment_map,
         nodes: nodes,
         edges: edges,
         unsupported: Enum.sort(unsupported)
       }}
    end
  end

  @doc "Looks up one canonical function identity."
  @spec function(t(), String.t()) :: {:ok, Function.t()} | {:error, map()}
  def function(%__MODULE__{nodes: nodes}, "function:" <> _rest = id) do
    case nodes do
      %{^id => %Function{} = function} -> {:ok, function}
      _ -> {:error, %{code: :function_not_found, focus: id}}
    end
  end

  def function(%__MODULE__{}, focus),
    do:
      {:error, %{code: :unsupported_focus, focus: focus, supported: "function:MODULE.name/arity"}}

  @doc "Returns direct managed function callers."
  @spec callers(t(), String.t()) :: [String.t()]
  def callers(graph, function_id) do
    graph.edges
    |> Enum.filter(
      &(&1.kind == :calls and &1.to == function_id and function_node?(graph, &1.from))
    )
    |> Enum.map(& &1.from)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Returns direct managed callees."
  @spec callees(t(), String.t()) :: [String.t()]
  def callees(graph, function_id) do
    graph.edges
    |> Enum.filter(
      &(&1.kind == :calls and &1.from == function_id and function_node?(graph, &1.to))
    )
    |> Enum.map(& &1.to)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Returns transitive upstream callers in deterministic breadth-first order."
  @spec upstream(t(), String.t()) :: [String.t()]
  def upstream(graph, function_id) do
    traverse(graph, [function_id], MapSet.new([function_id]), [])
  end

  @doc "Returns statically related test modules for a function."
  @spec related_tests(t(), String.t()) :: [String.t()]
  def related_tests(graph, function_id) do
    graph.edges
    |> Enum.filter(&(&1.kind == :tested_by and &1.from == function_id))
    |> Enum.map(fn edge -> graph.nodes |> Map.fetch!(edge.to) |> Map.fetch!(:module) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Returns a range-insensitive semantic signature used for round-trip checks."
  @spec semantic_signature(t()) :: term()
  def semantic_signature(graph) do
    node_signature =
      graph.nodes
      |> Enum.map(fn
        {id, %Function{} = function} ->
          {id,
           {:function, function.module, function.name, function.arity,
            Enum.map(function.clauses, fn clause ->
              {clause.ordinal, clause.patterns, clause.guard,
               Enum.map(clause.comparisons, &{&1.operator, &1.left, &1.right}),
               Enum.map(clause.calls, &{&1.module, &1.name, &1.arity, &1.imports})}
            end)}}

        {id, %Test{} = test} ->
          {id,
           {:test, test.module, test.name,
            Enum.map(test.calls, &{&1.module, &1.name, &1.arity, &1.imports})}}

        {id, node} ->
          {id, {node.__struct__, Map.get(node, :name)}}
      end)
      |> Enum.sort()

    edges = graph.edges |> Enum.map(&{&1.kind, &1.from, &1.to}) |> Enum.sort()
    {node_signature, edges, graph.unsupported}
  end

  defp build_nodes(fragments) do
    values =
      Enum.flat_map(fragments, fn fragment ->
        [fragment.module] ++
          fragment.functions ++
          Enum.flat_map(fragment.functions, fn function ->
            function.clauses ++ Enum.flat_map(function.clauses, & &1.comparisons)
          end) ++ fragment.tests
      end)

    values
    |> Enum.group_by(& &1.id)
    |> Enum.filter(fn {_id, grouped} -> length(grouped) > 1 end)
    |> Enum.sort_by(fn {id, grouped} -> {identity_priority(hd(grouped)), id} end)
    |> List.first()
    |> case do
      nil ->
        {:ok, Map.new(values, &{&1.id, &1})}

      {id, grouped} ->
        sources = grouped |> Enum.map(&source_identity/1) |> Enum.sort()
        {:error, %{code: :ambiguous_identity, id: id, sources: sources}}
    end
  end

  defp source_identity(node) do
    %{path: node.source.path, line: node.source.start_line, column: node.source.start_column}
  end

  defp identity_priority(%Module{}), do: 0
  defp identity_priority(%Function{}), do: 1
  defp identity_priority(%Test{}), do: 2
  defp identity_priority(_node), do: 3

  defp build_edges(fragments, nodes) do
    evidence = Evidence.derived_source()

    defines =
      Enum.flat_map(fragments, fn fragment ->
        module_id = fragment.module.id

        function_edges =
          Enum.flat_map(fragment.functions, fn function ->
            [edge(:defines, module_id, function.id, function.source, evidence)] ++
              Enum.map(function.clauses, &edge(:defines, function.id, &1.id, &1.source, evidence))
          end)

        test_edges =
          Enum.map(fragment.tests, &edge(:defines, module_id, &1.id, &1.source, evidence))

        function_edges ++ test_edges
      end)

    calls =
      Enum.flat_map(fragments, fn fragment ->
        function_calls =
          Enum.flat_map(fragment.functions, fn function ->
            function.clauses
            |> Enum.flat_map(& &1.calls)
            |> Enum.map(&resolved_call_edge(&1, nodes, evidence))
            |> Enum.reject(&is_nil/1)
          end)

        test_calls =
          fragment.tests
          |> Enum.flat_map(& &1.calls)
          |> Enum.map(&resolved_call_edge(&1, nodes, evidence))
          |> Enum.reject(&is_nil/1)

        function_calls ++ test_calls
      end)

    tested_by = tested_by_edges(calls, nodes, evidence)

    (defines ++ calls ++ tested_by)
    |> Enum.uniq_by(&{&1.kind, &1.from, &1.to, &1.source})
    |> Enum.sort_by(&{&1.kind, &1.from, &1.to, source_sort(&1.source)})
  end

  defp resolved_call_edge(call, nodes, evidence) do
    case resolve_call_target(call, nodes) do
      nil -> nil
      target -> edge(:calls, call.caller_id, target, call.source, evidence)
    end
  end

  defp resolve_call_target(call, nodes) do
    local_target = Identity.function(call.module, call.name, call.arity)

    if Map.has_key?(nodes, local_target) do
      local_target
    else
      call.imports
      |> List.wrap()
      |> Enum.map(&Identity.function(&1, call.name, call.arity))
      |> Enum.filter(&Map.has_key?(nodes, &1))
      |> case do
        [imported_target] -> imported_target
        _none_or_ambiguous -> nil
      end
    end
  end

  defp fragment_unsupported(fragments) do
    Enum.flat_map(fragments, fn fragment ->
      Enum.map(fragment.unsupported, &"#{fragment.path}: #{&1}")
    end)
  end

  defp unresolved_call_facts(fragments, nodes) do
    fragments
    |> Enum.flat_map(fn fragment ->
      calls =
        Enum.flat_map(fragment.functions, fn function ->
          Enum.flat_map(function.clauses, & &1.calls)
        end) ++ Enum.flat_map(fragment.tests, & &1.calls)

      calls
      |> Enum.filter(&(resolve_call_target(&1, nodes) == nil))
      |> Enum.map(fn call ->
        "#{fragment.path}: unresolved call #{call.module}.#{call.name}/#{call.arity} " <>
          "at #{call.source.start_line}:#{call.source.start_column}"
      end)
    end)
    |> Enum.uniq()
  end

  defp tested_by_edges(call_edges, nodes, evidence) do
    tests =
      nodes |> Enum.filter(fn {_id, node} -> match?(%Test{}, node) end) |> Enum.map(&elem(&1, 0))

    Enum.flat_map(tests, fn test_id ->
      reachable = reachable_from(call_edges, [test_id], MapSet.new())

      reachable
      |> Enum.filter(
        &function_node?(
          %__MODULE__{nodes: nodes, edges: [], fragments: %{}, revision: nil, unsupported: []},
          &1
        )
      )
      |> Enum.map(&edge(:tested_by, &1, test_id, nil, evidence))
    end)
  end

  defp reachable_from(_edges, [], visited), do: MapSet.to_list(visited)

  defp reachable_from(edges, [current | rest], visited) do
    next =
      edges
      |> Enum.filter(&(&1.kind == :calls and &1.from == current))
      |> Enum.map(& &1.to)
      |> Enum.reject(&MapSet.member?(visited, &1))

    reachable_from(edges, rest ++ next, Enum.reduce(next, visited, &MapSet.put(&2, &1)))
  end

  defp traverse(_graph, [], _visited, accumulated), do: accumulated

  defp traverse(graph, frontier, visited, accumulated) do
    next =
      frontier
      |> Enum.flat_map(&callers(graph, &1))
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.sort()

    visited = Enum.reduce(next, visited, &MapSet.put(&2, &1))
    traverse(graph, next, visited, accumulated ++ next)
  end

  defp function_node?(graph, id), do: match?(%Function{}, Map.get(graph.nodes, id))

  defp edge(kind, from, to, source, evidence),
    do: %Edge{kind: kind, from: from, to: to, source: source, evidence: evidence}

  defp source_sort(nil), do: {"", 0, 0}
  defp source_sort(source), do: {source.path, source.start_line, source.start_column}
end
