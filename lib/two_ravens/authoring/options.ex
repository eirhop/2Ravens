defmodule TwoRavens.Authoring.Options do
  @moduledoc false

  @type rule :: {:boolean, boolean()} | {:binary, String.t()}

  @spec validate(term(), keyword(rule())) :: {:ok, map()} | {:error, map()}
  def validate(options, schema) when is_list(options) do
    cond do
      not Keyword.keyword?(options) ->
        {:error, %{code: :invalid_options, value: options}}

      duplicate_keys(options) != [] ->
        {:error, %{code: :duplicate_options, options: duplicate_keys(options)}}

      true ->
        validate_keyword(options, schema)
    end
  end

  def validate(options, _schema), do: {:error, %{code: :invalid_options, value: options}}

  defp validate_keyword(options, schema) do
    unsupported = Keyword.keys(options) -- Keyword.keys(schema)

    if unsupported == [] do
      validate_values(options, schema)
    else
      {:error, %{code: :unsupported_options, options: Enum.sort(unsupported)}}
    end
  end

  defp validate_values(options, schema) do
    Enum.reduce_while(schema, {:ok, %{}}, fn {key, {type, default}}, {:ok, values} ->
      value = Keyword.get(options, key, default)
      validation_result(key, type, value, values)
    end)
  end

  defp validation_result(key, type, value, values) do
    if valid?(type, value) do
      {:cont, {:ok, Map.put(values, key, value)}}
    else
      {:halt, {:error, %{code: :invalid_option, option: key, expected: type, value: value}}}
    end
  end

  defp duplicate_keys(options) do
    options
    |> Keyword.keys()
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp valid?(:boolean, value), do: is_boolean(value)
  defp valid?(:binary, value), do: is_binary(value)
end
