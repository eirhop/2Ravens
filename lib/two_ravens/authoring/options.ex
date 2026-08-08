defmodule TwoRavens.Authoring.Options do
  @moduledoc false

  @type rule ::
          {:boolean, boolean()}
          | {:binary, String.t()}
          | {:optional_text, nil}
          | {:binary_list, [String.t()]}

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
    case normalize(type, value) do
      {:ok, normalized} ->
        {:cont, {:ok, Map.put(values, key, normalized)}}

      :error ->
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
  defp valid?(:optional_text, _value), do: false
  defp valid?(:binary_list, _value), do: false

  defp normalize(:optional_text, nil), do: {:ok, nil}

  defp normalize(:optional_text, value) when is_binary(value) do
    normalized = String.trim(value)

    if String.valid?(value) and byte_size(normalized) in 1..1000,
      do: {:ok, normalized},
      else: :error
  end

  defp normalize(:binary_list, values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..512)),
      do: {:ok, values},
      else: :error
  end

  defp normalize(type, value) do
    if valid?(type, value), do: {:ok, value}, else: :error
  end
end
