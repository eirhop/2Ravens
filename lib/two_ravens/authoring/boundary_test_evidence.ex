defmodule TwoRavens.Authoring.BoundaryTestEvidence do
  @moduledoc false

  alias TwoRavens.Authoring.Support
  alias TwoRavens.Graph
  alias TwoRavens.Identity
  alias TwoRavens.Project
  alias TwoRavens.Source.Comparison
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Syntax
  alias TwoRavens.Source.Test

  @type evidence ::
          %{status: :absent | :present | :unknown, reason: atom()}

  @spec analyze(Project.t(), Graph.t(), [String.t()], Comparison.t()) :: evidence()
  def analyze(_project, _graph, [], _comparison),
    do: %{status: :absent, reason: :no_related_tests}

  def analyze(project, graph, test_modules, %Comparison{} = comparison) do
    target = comparison.function_id
    relevant = MapSet.new([target | Graph.upstream(graph, target)])

    with :ok <- reject_unsupported_flow(graph, test_modules, relevant),
         {:ok, target_position} <- target_position(graph, comparison),
         {:ok, expected} <- parse_integer(comparison.right),
         {:ok, program} <- load_program(project, graph),
         {:ok, values} <-
           test_values(
             program,
             graph,
             test_modules,
             relevant,
             target,
             target_position
           ) do
      if expected in values,
        do: %{status: :present, reason: :boundary_value_derived},
        else: %{status: :absent, reason: :boundary_value_not_exercised}
    else
      _unsupported -> %{status: :unknown, reason: :test_argument_flow_not_derived}
    end
  end

  defp reject_unsupported_flow(graph, test_modules, relevant) do
    paths = relevant_paths(graph, test_modules, relevant)

    if Enum.any?(graph.unsupported, fn fact ->
         Enum.any?(paths, &String.starts_with?(fact, "#{&1}:"))
       end),
       do: :error,
       else: :ok
  end

  defp relevant_paths(graph, test_modules, relevant) do
    graph.nodes
    |> Map.values()
    |> Enum.flat_map(fn
      %Function{id: id, source: source} ->
        if MapSet.member?(relevant, id), do: [source.path], else: []

      %Test{module: module, source: source} ->
        if module in test_modules, do: [source.path], else: []

      _node ->
        []
    end)
    |> Enum.uniq()
  end

  defp target_position(graph, comparison) do
    with %Function{} = function <- Map.get(graph.nodes, comparison.function_id),
         clause when not is_nil(clause) <-
           Enum.find(function.clauses, &(&1.id == comparison.clause_id)),
         [position] <-
           clause.patterns
           |> Enum.with_index()
           |> Enum.filter(fn {pattern, _index} -> pattern == comparison.left end)
           |> Enum.map(&elem(&1, 1)) do
      {:ok, position}
    else
      _unsupported -> :error
    end
  end

  defp load_program(project, graph) do
    Enum.reduce_while(graph.fragments, {:ok, %{functions: %{}, tests: %{}}}, fn
      {_path, fragment}, {:ok, program} ->
        with {:ok, source} <- Support.read_source(project, fragment.path),
             {:ok, indexed} <- index_source(source) do
          {:cont, {:ok, merge_program(program, indexed)}}
        else
          _error -> {:halt, :error}
        end
    end)
  end

  defp index_source(source) do
    with {:ok, ast} <- Code.string_to_quoted(source),
         {:defmodule, _meta, [module_ast, [do: body]]} <- ast,
         {:ok, module} <- Syntax.alias_name(module_ast) do
      entries = Syntax.block_entries(body)
      aliases = aliases(entries)

      {:ok,
       Enum.reduce(entries, %{functions: %{}, tests: %{}}, fn entry, program ->
         index_entry(entry, module, aliases, program)
       end)}
    else
      _unsupported -> :error
    end
  end

  defp index_entry({:def, _meta, [head, body]}, module, aliases, program) do
    {name, arguments, _guard} = Syntax.function_head(head)
    id = Identity.function(module, Atom.to_string(name), length(arguments))

    clause = %{
      arguments: arguments,
      body: Keyword.fetch!(body, :do),
      module: module,
      aliases: aliases
    }

    update_in(
      program.functions,
      &Map.update(&1, id, [clause], fn clauses -> clauses ++ [clause] end)
    )
  end

  defp index_entry({:test, _meta, [name, body]}, module, aliases, program) do
    name = if is_binary(name), do: name, else: Macro.to_string(name)
    id = "test:#{module}:#{Identity.fingerprint(name)}"
    test = %{body: Keyword.fetch!(body, :do), module: module, aliases: aliases}
    put_in(program.tests[id], test)
  end

  defp index_entry(_entry, _module, _aliases, program), do: program

  defp merge_program(left, right) do
    %{
      functions: Map.merge(left.functions, right.functions),
      tests: Map.merge(left.tests, right.tests)
    }
  end

  defp test_values(program, graph, test_modules, relevant, target, target_position) do
    tests =
      graph.nodes
      |> Map.values()
      |> Enum.filter(fn
        %Test{module: module} = test ->
          module in test_modules and relevant_targets(graph, test.id, relevant) != []

        _node ->
          false
      end)

    if tests == [] do
      :error
    else
      Enum.reduce_while(tests, {:ok, []}, fn test, accumulated ->
        accumulate_test(
          test,
          accumulated,
          program,
          graph,
          relevant,
          target,
          target_position
        )
      end)
    end
  end

  defp accumulate_test(
         test,
         {:ok, values},
         program,
         graph,
         relevant,
         target,
         target_position
       ) do
    case derive_test_values(test, program, graph, relevant, target, target_position) do
      {:ok, derived} -> {:cont, {:ok, values ++ derived}}
      :error -> {:halt, :error}
    end
  end

  defp derive_test_values(test, program, graph, relevant, target, target_position) do
    with {:ok, indexed} <- Map.fetch(program.tests, test.id),
         {:ok, calls} <- relevant_calls(indexed, test.id, graph, relevant) do
      trace_calls(calls, program, graph, relevant, target, target_position)
    else
      _unsupported -> :error
    end
  end

  defp trace_calls(calls, program, graph, relevant, target, target_position) do
    Enum.reduce_while(calls, {:ok, []}, fn {callee, arguments}, {:ok, values} ->
      case trace(callee, arguments, program, graph, relevant, target, target_position, []) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp trace(target, arguments, _program, _graph, _relevant, target, target_position, _visited) do
    arguments
    |> Enum.fetch(target_position)
    |> case do
      {:ok, argument} -> evaluate_integer(argument)
      :error -> :error
    end
  end

  defp trace(
         function,
         arguments,
         program,
         graph,
         relevant,
         target,
         target_position,
         visited
       ) do
    with false <- function in visited,
         {[clause], true} <- {Map.get(program.functions, function, []), true},
         {:ok, bindings} <- bind(clause.arguments, arguments),
         {:ok, [{callee, downstream_arguments}]} <-
           relevant_calls(clause, function, graph, relevant) do
      substituted = Enum.map(downstream_arguments, &substitute(&1, bindings))

      trace(
        callee,
        substituted,
        program,
        graph,
        relevant,
        target,
        target_position,
        [function | visited]
      )
    else
      _unsupported -> :error
    end
  end

  defp relevant_calls(indexed, caller, graph, relevant) do
    if uncertain_control_flow?(indexed.body) do
      :error
    else
      compare_relevant_calls(indexed, caller, graph, relevant)
    end
  end

  defp compare_relevant_calls(indexed, caller, graph, relevant) do
    expected = relevant_targets(graph, caller, relevant)

    actual =
      indexed.body
      |> calls(indexed.module, indexed.aliases)
      |> Enum.filter(fn {callee, _arguments} -> MapSet.member?(relevant, callee) end)

    if Enum.sort(Enum.map(actual, &elem(&1, 0))) == Enum.sort(expected),
      do: {:ok, actual},
      else: :error
  end

  defp uncertain_control_flow?(ast) do
    {_ast, uncertain?} =
      Macro.prewalk(ast, false, fn
        {operator, _meta, [_left, _right]} = node, _found when operator in [:and, :or] ->
          {node, true}

        node, found ->
          {node, found}
      end)

    uncertain?
  end

  defp relevant_targets(graph, caller, relevant) do
    graph.edges
    |> Enum.filter(&(&1.kind == :calls and &1.from == caller and MapSet.member?(relevant, &1.to)))
    |> Enum.map(& &1.to)
  end

  defp calls(ast, module, aliases) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _dot_meta, [module_ast, name]}, _meta, arguments} = node, calls
        when is_atom(name) and is_list(arguments) ->
          call =
            case Syntax.alias_name(module_ast) do
              {:ok, remote} ->
                resolved = Map.get(aliases, remote, remote)
                {Identity.function(resolved, Atom.to_string(name), length(arguments)), arguments}

              :error ->
                nil
            end

          {node, add_call(calls, call)}

        {name, _meta, arguments} = node, calls when is_atom(name) and is_list(arguments) ->
          call = {Identity.function(module, Atom.to_string(name), length(arguments)), arguments}
          {node, [call | calls]}

        node, calls ->
          {node, calls}
      end)

    Enum.reverse(calls)
  end

  defp add_call(calls, nil), do: calls
  defp add_call(calls, call), do: [call | calls]

  defp bind(parameters, arguments) when length(parameters) == length(arguments) do
    parameters
    |> Enum.zip(arguments)
    |> Enum.reduce_while({:ok, %{}}, fn
      {{name, _meta, context}, argument}, {:ok, bindings}
      when is_atom(name) and (is_atom(context) or is_nil(context)) ->
        {:cont, {:ok, Map.put(bindings, name, argument)}}

      _unsupported, _bindings ->
        {:halt, :error}
    end)
  end

  defp bind(_parameters, _arguments), do: :error

  defp substitute(ast, bindings) do
    Macro.prewalk(ast, fn
      {name, _meta, context} = variable
      when is_atom(name) and (is_atom(context) or is_nil(context)) ->
        Map.get(bindings, name, variable)

      node ->
        node
    end)
  end

  defp evaluate_integer(value) when is_integer(value), do: {:ok, value}

  defp evaluate_integer({operator, _meta, [left, right]}) when operator in [:+, :-, :*] do
    with {:ok, left} <- evaluate_integer(left),
         {:ok, right} <- evaluate_integer(right) do
      {:ok, arithmetic(operator, left, right)}
    end
  end

  defp evaluate_integer({:div, _meta, [left, right]}) do
    with {:ok, left} <- evaluate_integer(left),
         {:ok, right} when right != 0 <- evaluate_integer(right) do
      {:ok, div(left, right)}
    else
      _unsupported -> :error
    end
  end

  defp evaluate_integer({operator, _meta, [value]}) when operator in [:+, :-] do
    with {:ok, value} <- evaluate_integer(value) do
      {:ok, if(operator == :-, do: -value, else: value)}
    end
  end

  defp evaluate_integer(_value), do: :error

  defp arithmetic(:+, left, right), do: left + right
  defp arithmetic(:-, left, right), do: left - right
  defp arithmetic(:*, left, right), do: left * right

  defp aliases(entries) do
    entries
    |> Enum.flat_map(fn
      {:alias, _meta, [alias_ast | options]} ->
        alias_entry(alias_ast, List.flatten(options))

      _entry ->
        []
    end)
    |> Map.new()
  end

  defp alias_entry(alias_ast, options) do
    with {:ok, full} <- Syntax.alias_name(alias_ast),
         {:ok, short} <- alias_short_name(full, Keyword.get(options, :as)) do
      [{short, full}]
    else
      _unsupported -> []
    end
  end

  defp alias_short_name(full, nil), do: {:ok, full |> String.split(".") |> List.last()}
  defp alias_short_name(_full, as_ast), do: Syntax.alias_name(as_ast)

  defp parse_integer(value) do
    case value |> String.replace("_", "") |> Integer.parse() do
      {integer, ""} -> {:ok, integer}
      _invalid -> :error
    end
  end
end
