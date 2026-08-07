defmodule TwoRavens.Source.Facts do
  @moduledoc false

  alias TwoRavens.Identity
  alias TwoRavens.Source.Call
  alias TwoRavens.Source.Comparison
  alias TwoRavens.Source.Range
  alias TwoRavens.Source.Syntax

  @comparison_atoms [:==, :!=, :===, :!==, :<, :<=, :>, :>=]
  @ignored_calls [
    :__aliases__,
    :__block__,
    :{},
    :<<>>,
    :%,
    :%{},
    :.,
    :=,
    :^,
    :@,
    :|,
    :when,
    :and,
    :or,
    :not,
    :in,
    :+,
    :-,
    :*,
    :/,
    :++,
    :--,
    :<>,
    :==,
    :!=,
    :===,
    :!==,
    :<,
    :<=,
    :>,
    :>=,
    :div,
    :assert,
    :refute
  ]

  @spec calls(Macro.t() | nil, String.t(), map(), [String.t()], String.t(), String.t(), struct()) ::
          [Call.t()]
  def calls(nil, _module_name, _aliases, _imports, _caller_id, _path, _evidence), do: []

  def calls(ast, module_name, aliases, imports, caller_id, path, evidence) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _dot_meta, [module_ast, name]}, _meta, args} = node, calls
        when is_atom(name) and is_list(args) ->
          call =
            case Syntax.alias_name(module_ast) do
              {:ok, remote_module} ->
                resolved_module = Map.get(aliases, remote_module, remote_module)

                call(
                  caller_id,
                  resolved_module,
                  name,
                  args,
                  [],
                  {"#{remote_module}.#{name}", Syntax.source_meta(module_ast)},
                  path,
                  evidence
                )

              :error ->
                nil
            end

          {node, maybe_add(calls, call)}

        {name, meta, args} = node, calls
        when is_atom(name) and is_list(args) and name not in @ignored_calls ->
          call =
            call(
              caller_id,
              module_name,
              name,
              args,
              imports,
              {Atom.to_string(name), meta},
              path,
              evidence
            )

          {node, [call | calls]}

        node, calls ->
          {node, calls}
      end)

    calls
    |> Enum.uniq_by(fn call ->
      {call.module, call.name, call.arity, call.imports, call.source.start_line,
       call.source.start_column}
    end)
    |> Enum.sort_by(fn call -> {call.source.start_line, call.source.start_column} end)
  end

  @spec comparisons(Macro.t() | nil, String.t(), String.t(), String.t(), String.t(), struct()) ::
          [Comparison.t()]
  def comparisons(nil, _function_id, _clause_fingerprint, _path, _source, _evidence), do: []

  def comparisons(ast, function_id, clause_fingerprint, path, source, evidence) do
    {_ast, comparisons} =
      Macro.prewalk(ast, [], fn
        {operator, meta, [left, right]} = node, comparisons when operator in @comparison_atoms ->
          operator_string = Atom.to_string(operator)

          {left_source, right_source} =
            comparison_operands(source, meta, operator_string, left, right)

          expression_fingerprint =
            Identity.fingerprint(
              {Syntax.normalize_ast(left), operator, Syntax.normalize_ast(right)}
            )

          comparison = %Comparison{
            id: "pending",
            function_id: function_id,
            clause_id: "pending",
            clause_fingerprint: clause_fingerprint,
            fingerprint: expression_fingerprint,
            operator: operator_string,
            left: left_source,
            right: right_source,
            source: Range.token(path, meta, String.length(operator_string)),
            evidence: evidence
          }

          {node, [comparison | comparisons]}

        node, comparisons ->
          {node, comparisons}
      end)

    comparisons
    |> Enum.uniq_by(&{&1.fingerprint, &1.source.start_line, &1.source.start_column})
    |> Enum.sort_by(&{&1.source.start_line, &1.source.start_column})
  end

  defp call(caller_id, module, name, args, imports, {reference, meta}, path, evidence) do
    %Call{
      caller_id: caller_id,
      module: module,
      name: Atom.to_string(name),
      arity: length(args),
      imports: imports,
      source: Range.token(path, meta, String.length(reference)),
      evidence: evidence
    }
  end

  defp comparison_operands(source, meta, operator, left, right) do
    line = source |> String.split("\n", trim: false) |> Enum.at(meta[:line] - 1, "")
    column = meta[:column] || 1
    before = String.slice(line, 0, max(column - 1, 0))
    after_operator = String.slice(line, max(column - 1 + String.length(operator), 0)..-1//1)

    left_source =
      case Regex.run(~r/([A-Za-z_][A-Za-z0-9_!?]*)\s*$/, before, capture: :all_but_first) do
        [value] -> value
        _ -> Macro.to_string(left)
      end

    right_source =
      case Regex.run(~r/^\s*([0-9][0-9_]*|:[A-Za-z_][A-Za-z0-9_!?]*)/, after_operator,
             capture: :all_but_first
           ) do
        [value] -> value
        _ -> Macro.to_string(right)
      end

    {left_source, right_source}
  end

  defp maybe_add(values, nil), do: values
  defp maybe_add(values, value), do: [value | values]
end
