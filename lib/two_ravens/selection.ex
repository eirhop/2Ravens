defmodule TwoRavens.Selection do
  @moduledoc "Bounded semantic selectors over one exact graph revision."

  alias TwoRavens.Discovery
  alias TwoRavens.EditHandle
  alias TwoRavens.Graph
  alias TwoRavens.Repository
  alias TwoRavens.Source
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Module
  alias TwoRavens.Source.ModuleForm
  alias TwoRavens.Source.Test

  @max_source_bytes 32_000
  @max_functions 500
  @max_tests 500
  @max_test_targets 500

  @doc "Resolves validated selectors independently against the supplied graph and source."
  @spec resolve(Graph.t(), %{String.t() => String.t() | nil}, [map()]) :: {:ok, [map()]}
  def resolve(%Graph{} = graph, files, selectors) when is_map(files) and is_list(selectors) do
    {:ok,
     Enum.map(selectors, fn selector ->
       case selector do
         %{validation_error: reason} ->
           %{focus: selector.focus, error: reason, omitted: true}

         _valid ->
           resolve_selector(graph, files, selector)
       end
     end)}
  end

  defp resolve_selector(graph, files, selector) do
    case resolve_one(graph, files, selector) do
      {:ok, result} ->
        case Map.get(selector, :validation_warning) do
          nil -> result
          warning -> Map.put(result, :warnings, [warning])
        end

      {:error, reason} ->
        %{focus: selector.focus, error: reason, omitted: true}
    end
  end

  defp resolve_one(graph, files, %{focus: "function:" <> _ = focus, include: include}) do
    case Map.get(graph.nodes, focus) do
      %Function{} = function ->
        with {:ok, result} <- maybe_source(%{focus: focus}, graph, files, function, include) do
          {:ok, Enum.reduce(include, result, &add_function_field(&1, &2, graph, function))}
        end

      _other ->
        {:error,
         %{
           code: :selector_target_not_found,
           focus: focus,
           suggestions: Discovery.focus_suggestions(graph, focus, 5)
         }}
    end
  end

  defp resolve_one(graph, _files, %{focus: "module:" <> _ = focus, include: include}) do
    case Map.get(graph.nodes, focus) do
      %Module{name: module} ->
        result =
          Enum.reduce(include, %{focus: focus}, fn
            :functions, selected -> merge_bounded(selected, inventory(graph, module))
            :forms, selected -> Map.put(selected, :forms, module_forms(graph, module))
            :tests, selected -> merge_bounded(selected, module_tests(graph, module))
          end)

        {:ok, result}

      _other ->
        {:error,
         %{
           code: :selector_target_not_found,
           focus: focus,
           suggestions: Discovery.focus_suggestions(graph, focus, 5)
         }}
    end
  end

  defp resolve_one(graph, files, %{focus: "test:" <> _ = focus, include: include}) do
    case Map.get(graph.nodes, focus) do
      %Test{} = test ->
        with {:ok, result} <- maybe_test_source(%{focus: focus}, graph, files, test, include) do
          {:ok, Enum.reduce(include, result, &add_test_field(&1, &2, graph, test, files))}
        end

      _other ->
        {:error, %{code: :selector_target_not_found, focus: focus}}
    end
  end

  defp add_function_field(:source, result, _graph, _function), do: result

  defp add_function_field(:path, result, _graph, function) do
    Map.merge(result, %{path: function.source.path, start_line: function.source.start_line})
  end

  defp add_function_field(:clauses, result, _graph, function),
    do: Map.put(result, :clauses, function.clauses)

  defp add_function_field(:callers, result, graph, function),
    do: Map.put(result, :callers, Graph.callers(graph, function.id))

  defp add_function_field(:callees, result, graph, function),
    do: Map.put(result, :callees, Graph.callees(graph, function.id))

  defp add_function_field(:tests, result, graph, function),
    do: Map.put(result, :tests, Graph.related_tests(graph, function.id))

  defp add_function_field(:docs, result, _graph, function),
    do: Map.put(result, :documentation, function.documentation)

  defp add_function_field(:editable, result, graph, function),
    do: Map.put(result, :editable, editables(graph, function))

  defp add_function_field(:evidence, result, _graph, _function),
    do: Map.put(result, :evidence, [])

  defp add_test_field(:source, result, _graph, _test, _files), do: result

  defp add_test_field(:targets, result, graph, test, _files),
    do: Map.put(result, :targets, Graph.test_targets(graph, test.id))

  defp add_test_field(:path, result, _graph, test, _files) do
    Map.put(result, :path, %{
      path: test.source.path,
      start_line: test.source.start_line,
      end_line: test.source.end_line
    })
  end

  defp add_test_field(:editable, result, _graph, test, files) do
    source = files |> Map.fetch!(test.source.path) |> Source.select(test.source)

    Map.put(result, :editable, %{
      hash: Repository.hash(source),
      operations: ["patch", "replace", "delete"]
    })
  end

  defp add_test_field(:evidence, result, _graph, test, _files),
    do: Map.put(result, :evidence, test.evidence)

  defp inventory(graph, module) do
    functions =
      graph.nodes
      |> Map.values()
      |> Enum.filter(&match?(%Function{module: ^module}, &1))
      |> Enum.sort_by(&{&1.visibility != :public, &1.name, &1.arity})

    {visible, remaining} = Enum.split(functions, @max_functions)

    %{
      functions: Enum.map(visible, &function_summary/1),
      total_functions: length(functions),
      truncated: remaining != []
    }
  end

  defp module_forms(graph, module) do
    graph.nodes
    |> Map.values()
    |> Enum.filter(&match?(%ModuleForm{module: ^module}, &1))
    |> Enum.sort_by(& &1.id)
    |> Enum.map(fn form ->
      %{focus: form.id, source: form.form, semantics: form.semantics}
    end)
  end

  defp module_tests(graph, module) do
    tests =
      graph.nodes
      |> Map.values()
      |> Enum.filter(&match?(%Test{module: ^module}, &1))
      |> Enum.sort_by(&{&1.name, &1.id})

    {visible, remaining} = Enum.split(tests, @max_tests)
    summaries = Enum.map(visible, &test_summary(graph, &1))

    %{
      tests: summaries,
      total_tests: length(tests),
      truncated: remaining != [] or Enum.any?(summaries, & &1.targets_truncated)
    }
  end

  defp test_summary(graph, test) do
    targets = Graph.test_targets(graph, test.id)
    {visible, remaining} = Enum.split(targets, @max_test_targets)

    %{
      focus: test.id,
      name: test.name,
      targets: visible,
      total_targets: length(targets),
      targets_truncated: remaining != []
    }
  end

  defp merge_bounded(selected, values) do
    truncated = Map.get(selected, :truncated, false) or Map.get(values, :truncated, false)
    selected |> Map.merge(values) |> Map.put(:truncated, truncated)
  end

  defp function_summary(function) do
    %{
      focus: function.id,
      name: function.name,
      arity: function.arity,
      visibility: function.visibility,
      clauses: length(function.clauses)
    }
  end

  defp maybe_source(result, graph, files, function, include) do
    if :source in include do
      source = files |> Map.fetch!(function.source.path) |> Source.select(function.source)

      if byte_size(source) <= @max_source_bytes do
        {:ok, Map.merge(result, %{source: source, content_bytes: byte_size(source)})}
      else
        {:error,
         %{
           code: :selection_too_large,
           focus: function.id,
           content_bytes: byte_size(source),
           limit_bytes: @max_source_bytes,
           revision: graph.revision.working_hash
         }}
      end
    else
      {:ok, result}
    end
  end

  defp maybe_test_source(result, graph, files, test, include) do
    if :source in include do
      source = files |> Map.fetch!(test.source.path) |> Source.select(test.source)

      if byte_size(source) <= @max_source_bytes do
        {:ok, Map.merge(result, %{source: source, content_bytes: byte_size(source)})}
      else
        {:error,
         %{
           code: :selection_too_large,
           focus: test.id,
           content_bytes: byte_size(source),
           limit_bytes: @max_source_bytes,
           revision: graph.revision.working_hash
         }}
      end
    else
      {:ok, result}
    end
  end

  defp editables(graph, function) do
    hash = Map.fetch!(graph.revision.file_hashes, function.source.path)

    function.clauses
    |> Enum.flat_map(& &1.comparisons)
    |> Enum.map(fn comparison ->
      %{
        handle: EditHandle.encode(hash, comparison),
        property: "operator",
        value: comparison.operator
      }
    end)
  end
end
