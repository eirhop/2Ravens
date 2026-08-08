defmodule TwoRavens.Selector do
  @moduledoc false

  @max 32
  @max_includes 12
  @function_includes ~w(source path clauses callers callees tests editable docs evidence)
  @module_includes ~w(functions forms tests)
  @test_includes ~w(source targets path editable evidence)
  @include_atoms %{
    "source" => :source,
    "clauses" => :clauses,
    "callers" => :callers,
    "callees" => :callees,
    "tests" => :tests,
    "editable" => :editable,
    "docs" => :docs,
    "evidence" => :evidence,
    "functions" => :functions,
    "forms" => :forms,
    "targets" => :targets,
    "path" => :path
  }

  @spec validate(term()) :: {:ok, [map()]} | {:error, map()}
  def validate(selectors)
      when is_list(selectors) and selectors != [] and length(selectors) <= @max do
    validated =
      selectors
      |> Enum.with_index()
      |> Enum.map(fn {selector, index} ->
        case validate_one(selector, index) do
          {:ok, value} -> value
          {:error, reason} -> invalid_selector(selector, index, reason)
        end
      end)

    {:ok, validated}
  end

  def validate(_selectors),
    do: {:error, %{code: :invalid_selectors, reason: :bounded_list_required, limit: @max}}

  @spec validate_strict(term()) :: {:ok, [map()]} | {:error, map()}
  def validate_strict(selectors)
      when is_list(selectors) and selectors != [] and length(selectors) <= @max do
    selectors
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {selector, index}, {:ok, values} ->
      case validate_one(selector, index) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end)
  end

  def validate_strict(_selectors),
    do: {:error, %{code: :invalid_selectors, reason: :bounded_list_required, limit: @max}}

  defp validate_one(%{"focus" => focus, "include" => include} = selector, index)
       when map_size(selector) == 2 do
    validate_fields(focus, include, index)
  end

  defp validate_one(selector, index) when is_map(selector) do
    {:error,
     %{
       code: :invalid_selector,
       selector: index,
       reason: :exact_focus_and_include_fields_required,
       fields: selector |> Map.keys() |> Enum.filter(&is_binary/1) |> Enum.sort()
     }}
  end

  defp validate_one(_selector, index), do: error(index, :map_required)

  defp validate_fields(focus, include, index)
       when is_binary(focus) and byte_size(focus) in 1..500 and is_list(include) and
              include != [] and length(include) <= @max_includes do
    with {:ok, allowed} <- validate_focus(focus, index),
         {:ok, include, warning} <- validate_includes(include, allowed, index) do
      selector = %{focus: focus, include: Enum.map(include, &Map.fetch!(@include_atoms, &1))}
      {:ok, maybe_warn(selector, warning)}
    end
  end

  defp validate_fields(_focus, _include, index), do: error(index, :invalid_focus_or_include)

  defp validate_focus(focus, index) do
    case allowed(focus) do
      nil -> error(index, :unsupported_focus)
      allowed -> {:ok, allowed}
    end
  end

  defp validate_includes(include, allowed, index) do
    cond do
      not Enum.all?(include, &is_binary/1) ->
        error(index, :string_include_values_required)

      length(Enum.uniq(include)) != length(include) ->
        error(index, :duplicate_includes)

      true ->
        supported = Enum.filter(include, &(&1 in allowed))
        unsupported = Enum.reject(include, &(&1 in allowed))
        supported_includes(supported, unsupported, allowed, index)
    end
  end

  defp supported_includes([], unsupported, allowed, index) do
    {:error,
     %{
       code: :unsupported_selector_includes,
       selector: index,
       includes: unsupported,
       allowed: allowed,
       corrected_selector: nil
     }}
  end

  defp supported_includes(supported, [], _allowed, _index), do: {:ok, supported, nil}

  defp supported_includes(supported, unsupported, allowed, index) do
    warning = %{
      code: :unsupported_selector_includes,
      selector: index,
      includes: unsupported,
      allowed: allowed,
      corrected_selector: %{focus: nil, include: supported}
    }

    {:ok, supported, warning}
  end

  defp invalid_selector(selector, index, reason) do
    focus =
      if is_map(selector) and is_binary(selector["focus"]),
        do: selector["focus"],
        else: "selector:#{index}"

    %{focus: focus, include: [], validation_error: reason}
  end

  defp maybe_warn(selector, nil), do: selector

  defp maybe_warn(selector, warning) do
    warning = put_in(warning, [:corrected_selector, :focus], selector.focus)
    Map.put(selector, :validation_warning, warning)
  end

  defp allowed("function:" <> _rest), do: @function_includes
  defp allowed("module:" <> _rest), do: @module_includes
  defp allowed("test:" <> _rest), do: @test_includes
  defp allowed(_focus), do: nil

  defp error(index, reason),
    do: {:error, %{code: :invalid_selector, selector: index, reason: reason}}
end
