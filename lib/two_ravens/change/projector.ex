defmodule TwoRavens.Change.Projector do
  @moduledoc false

  alias TwoRavens.Authoring.Support
  alias TwoRavens.Graph
  alias TwoRavens.Source

  @spec order_new_modules(Graph.t(), %{String.t() => String.t() | nil}, MapSet.t(String.t())) ::
          {:ok, %{String.t() => String.t() | nil}} | {:error, map()}
  def order_new_modules(%Graph{} = graph, files, new_paths) do
    Enum.reduce_while(new_paths, {:ok, files}, fn path, {:ok, current} ->
      case order_path(graph, path, current[path]) do
        {:ok, source} -> {:cont, {:ok, Map.put(current, path, source)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp order_path(_graph, _path, nil), do: {:ok, nil}

  defp order_path(graph, path, source) do
    fragment = Map.fetch!(graph.fragments, path)
    functions = Enum.sort_by(fragment.functions, & &1.source.start_line)

    cond do
      length(functions) < 2 -> {:ok, source}
      interleaved_forms?(fragment, functions) -> {:ok, source}
      true -> reorder_functions(graph, path, source, functions)
    end
  end

  defp interleaved_forms?(fragment, functions) do
    first = hd(functions).source.start_line
    last = List.last(functions).source.end_line
    Enum.any?(fragment.module_forms, &(&1.source.start_line in first..last))
  end

  defp reorder_functions(graph, path, source, functions) do
    ordered = hierarchy_order(graph, functions)

    if Enum.map(ordered, & &1.id) == Enum.map(functions, & &1.id) do
      {:ok, source}
    else
      replace_function_region(path, source, functions, ordered)
    end
  end

  defp replace_function_region(path, source, functions, ordered) do
    first = hd(functions).source.start_line
    last = List.last(functions).source.end_line
    lines = String.split(source, "\n", trim: false)

    replacement =
      ordered
      |> Enum.map_join("\n\n", fn function ->
        source |> Source.select(function.source) |> String.trim_trailing()
      end)
      |> String.split("\n", trim: false)

    changed =
      (Enum.take(lines, first - 1) ++ replacement ++ Enum.drop(lines, last))
      |> Enum.join("\n")

    Support.format(changed, path)
  end

  defp hierarchy_order(graph, functions) do
    ids = MapSet.new(functions, & &1.id)

    source_order =
      Map.new(Enum.with_index(functions), fn {function, index} -> {function.id, index} end)

    outgoing =
      Map.new(functions, fn function ->
        callees = Graph.callees(graph, function.id) |> Enum.filter(&MapSet.member?(ids, &1))
        {function.id, callees}
      end)

    indegree =
      Enum.reduce(outgoing, Map.new(functions, &{&1.id, 0}), fn {_from, targets}, degrees ->
        Enum.reduce(targets, degrees, &Map.update!(&2, &1, fn degree -> degree + 1 end))
      end)

    {ordered_ids, remaining} = kahn(outgoing, indegree, source_order, [])

    cycle_ids =
      remaining
      |> Enum.filter(fn {_id, degree} -> degree > 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&Map.fetch!(source_order, &1))

    all_ids = ordered_ids ++ cycle_ids
    by_id = Map.new(functions, &{&1.id, &1})

    all_ids
    |> Enum.map(&Map.fetch!(by_id, &1))
    |> Enum.sort_by(fn function ->
      {visibility_rank(function.visibility), Enum.find_index(all_ids, &(&1 == function.id))}
    end)
  end

  defp kahn(outgoing, indegree, source_order, ordered) do
    ready =
      indegree
      |> Enum.filter(fn {_id, degree} -> degree == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(&Map.fetch!(source_order, &1))

    case ready do
      [] ->
        {Enum.reverse(ordered), indegree}

      [next | _rest] ->
        degrees =
          outgoing
          |> Map.fetch!(next)
          |> Enum.reduce(Map.delete(indegree, next), fn target, current ->
            Map.update!(current, target, &(&1 - 1))
          end)

        kahn(outgoing, degrees, source_order, [next | ordered])
    end
  end

  defp visibility_rank(:private), do: 1
  defp visibility_rank(_public), do: 0
end
