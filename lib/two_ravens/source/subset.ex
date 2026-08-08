defmodule TwoRavens.Source.Subset do
  @moduledoc false

  alias TwoRavens.Source.Syntax

  @comparison_atoms [:==, :!=, :===, :!==, :<, :<=, :>, :>=]
  @guard_atoms @comparison_atoms ++ [:and, :or, :not]
  @disallowed_nested [
    :def,
    :defp,
    :defmodule,
    :case,
    :cond,
    :if,
    :unless,
    :with,
    :fn,
    :receive,
    :try,
    :quote,
    :unquote,
    :for,
    :alias,
    :import,
    :use,
    :test,
    :@
  ]

  @spec top_level(Macro.t()) :: :supported | {:unsupported, String.t()}
  def top_level({:def, _meta, [_head, body]}) when is_list(body), do: :supported
  def top_level({:defp, _meta, [_head, body]}) when is_list(body), do: :supported
  def top_level({:test, _meta, [_name, body]}) when is_list(body), do: :supported

  def top_level({:use, _meta, [{:__aliases__, _, [:ExUnit, :Case]} | _options]}),
    do: :supported

  def top_level({:alias, _meta, [alias_ast | options]}) do
    case Syntax.static_aliases(alias_ast, options) do
      {:ok, _aliases} -> :supported
      :error -> {:unsupported, "unsupported top-level alias"}
    end
  end

  def top_level({:import, _meta, [{:__aliases__, _, _parts} | _options]}), do: :supported

  def top_level({:@, _meta, [{:moduledoc, _inner_meta, [value]}]})
      when is_binary(value) or value == false,
      do: :supported

  def top_level({:@, _meta, [{:doc, _inner_meta, [value]}]})
      when is_binary(value) or value == false,
      do: :supported

  def top_level({:@, _meta, [{:spec, _inner_meta, [_value]}]}), do: :supported

  def top_level({:@, _meta, [{name, _inner_meta, [_value]}]})
      when name in [:impl, :deprecated],
      do: :supported

  def top_level(other),
    do: {:unsupported, "unsupported top-level form: #{Syntax.form_name(other)}"}

  @spec inside(Macro.t()) :: [String.t()]
  def inside({:def, _meta, [head, body_keyword]}) do
    {_name, arguments, guard} = Syntax.function_head(head)
    body = Keyword.fetch!(body_keyword, :do)

    []
    |> maybe_unsupported(Enum.all?(arguments, &valid_pattern?/1), "unsupported function pattern")
    |> maybe_unsupported(valid_guard?(guard), "unsupported guard expression")
    |> maybe_unsupported(valid_expression?(body), "unsupported function body expression")
  end

  def inside({:defp, _meta, [head, body_keyword]}),
    do: inside({:def, [], [head, body_keyword]})

  def inside({:test, _meta, [name, body_keyword]}) do
    []
    |> maybe_unsupported(is_binary(name), "unsupported test name")
    |> maybe_unsupported(
      valid_expression?(Keyword.fetch!(body_keyword, :do)),
      "unsupported test body expression"
    )
  end

  def inside(_entry), do: []

  defp maybe_unsupported(facts, true, _fact), do: facts
  defp maybe_unsupported(facts, false, fact), do: facts ++ [fact]

  defp valid_pattern?(value) when is_atom(value) or is_number(value) or is_binary(value), do: true
  defp valid_pattern?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp valid_pattern?({:{}, _meta, values}), do: Enum.all?(values, &valid_pattern?/1)
  defp valid_pattern?(values) when is_list(values), do: Enum.all?(values, &valid_pattern?/1)
  defp valid_pattern?(_value), do: false

  defp valid_guard?(nil), do: true

  defp valid_guard?({name, _meta, arguments}) when name in @guard_atoms and is_list(arguments),
    do: Enum.all?(arguments, &valid_guard_operand?/1)

  defp valid_guard?(_guard), do: false

  defp valid_guard_operand?({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: true

  defp valid_guard_operand?(value) when is_atom(value) or is_number(value) or is_binary(value),
    do: true

  defp valid_guard_operand?(guard), do: valid_guard?(guard)

  defp valid_expression?(value)
       when is_atom(value) or is_number(value) or is_binary(value) or is_nil(value),
       do: true

  defp valid_expression?(values) when is_list(values), do: Enum.all?(values, &valid_expression?/1)

  defp valid_expression?({:__block__, _meta, expressions}),
    do: Enum.all?(expressions, &valid_expression?/1)

  defp valid_expression?({:=, _meta, [pattern, expression]}),
    do: valid_pattern?(pattern) and valid_expression?(expression)

  defp valid_expression?({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: true

  defp valid_expression?({{:., _dot_meta, [module_ast, name]}, _meta, arguments})
       when is_atom(name) and is_list(arguments) do
    match?({:ok, _module}, Syntax.alias_name(module_ast)) and
      Enum.all?(arguments, &valid_expression?/1)
  end

  defp valid_expression?({:{}, _meta, values}), do: Enum.all?(values, &valid_expression?/1)

  defp valid_expression?({name, _meta, arguments}) when is_atom(name) and is_list(arguments) do
    name_string = Atom.to_string(name)

    name not in @disallowed_nested and
      (Regex.match?(~r/^[a-z_][A-Za-z0-9_!?]*$/, name_string) or
         name in (@comparison_atoms ++ [:+, :-, :*, :/, :and, :or, :not])) and
      Enum.all?(arguments, &valid_expression?/1)
  end

  defp valid_expression?(_expression), do: false
end
