defmodule TwoRavens.SemanticStore.Projection do
  @moduledoc false

  alias TwoRavens.Graph
  alias TwoRavens.Identity
  alias TwoRavens.Source.Clause
  alias TwoRavens.Source.Comparison
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Module
  alias TwoRavens.Source.ModuleForm
  alias TwoRavens.Source.Test

  @type projection_node :: %{
          semantic_key: String.t(),
          kind: String.t(),
          fingerprint: String.t(),
          source: TwoRavens.SourceRange.t(),
          content_hash: String.t()
        }

  @doc false
  @spec nodes(Graph.t()) :: [projection_node()]
  def nodes(%Graph{} = graph) do
    graph.nodes
    |> Map.values()
    |> Enum.map(fn node ->
      %{
        semantic_key: node.id,
        kind: kind(node),
        fingerprint: fingerprint(node, graph),
        source: node.source,
        content_hash: Map.fetch!(graph.revision.file_hashes, node.source.path)
      }
    end)
    |> Enum.sort_by(& &1.semantic_key)
  end

  @doc false
  @spec relations(Graph.t()) :: [map()]
  def relations(%Graph{} = graph) do
    graph.edges
    |> Enum.map(fn edge ->
      %{type: Atom.to_string(edge.kind), source: edge.from, target: edge.to, range: edge.source}
    end)
    |> Enum.sort_by(&{&1.type, &1.source, &1.target, range_sort(&1.range)})
  end

  @doc false
  @spec signature(Graph.t()) :: term()
  def signature(%Graph{} = graph) do
    node_signature = Enum.map(nodes(graph), &{&1.kind, &1.semantic_key, &1.fingerprint})
    relation_signature = Enum.map(relations(graph), &{&1.type, &1.source, &1.target})
    {node_signature, relation_signature}
  end

  defp kind(%Module{}), do: "module"
  defp kind(%ModuleForm{}), do: "module_form"
  defp kind(%Function{}), do: "function"
  defp kind(%Clause{}), do: "clause"
  defp kind(%Comparison{}), do: "comparison"
  defp kind(%Test{}), do: "test"

  defp fingerprint(%Module{id: id, documentation: documentation}, graph) do
    children =
      graph.edges
      |> Enum.filter(&(&1.kind == :defines and &1.from == id))
      |> Enum.map(fn edge ->
        child = Map.fetch!(graph.nodes, edge.to)
        {kind(child), fingerprint(child, graph)}
      end)
      |> Enum.sort()

    Identity.fingerprint({:module, documentation, children})
  end

  defp fingerprint(%Function{} = function, _graph) do
    clauses =
      Enum.map(function.clauses, fn clause ->
        {clause.ordinal, clause.patterns, clause.guard,
         Enum.map(clause.comparisons, &{&1.operator, &1.left, &1.right}),
         Enum.map(clause.calls, &{&1.name, &1.arity})}
      end)

    Identity.fingerprint(
      {:function, function.arity, function.documentation, function.specifications, clauses}
    )
  end

  defp fingerprint(%Clause{fingerprint: fingerprint}, _graph), do: fingerprint
  defp fingerprint(%ModuleForm{fingerprint: fingerprint}, _graph), do: fingerprint
  defp fingerprint(%Comparison{fingerprint: fingerprint}, _graph), do: fingerprint

  defp fingerprint(%Test{} = test, _graph) do
    Identity.fingerprint({:test, test.name, Enum.map(test.calls, &{&1.name, &1.arity})})
  end

  defp range_sort(nil), do: {"", 0, 0}
  defp range_sort(range), do: {range.path, range.start_line, range.start_column}
end
