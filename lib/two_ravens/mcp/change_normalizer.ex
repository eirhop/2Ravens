defmodule TwoRavens.MCP.ChangeNormalizer do
  @moduledoc false

  alias TwoRavens.Change.SourceBundle

  @doc false
  @spec normalize(map()) :: map()
  def normalize(request) when is_map(request) do
    case Map.get(request, "operations") do
      operations when is_list(operations) ->
        Map.put(request, "operations", Enum.map(operations, &normalize_operation/1))

      _other ->
        request
    end
  end

  defp normalize_operation(operation) when is_map(operation) do
    operation
    |> normalize_operation_name()
    |> normalize_source_collection()
  end

  defp normalize_operation(operation), do: operation

  defp normalize_operation_name(%{"operation" => op} = operation)
       when is_binary(op) and not is_map_key(operation, "op") do
    operation |> Map.delete("operation") |> Map.put("op", op)
  end

  defp normalize_operation_name(operation), do: operation

  defp normalize_source_collection(operation) do
    aliases = Enum.filter(~w(files sources), &Map.has_key?(operation, &1))

    with [alias_key] <- aliases,
         false <- Map.has_key?(operation, "text"),
         "create" <- Map.get(operation, "op"),
         {:ok, source} <- joined_source(operation[alias_key]) do
      operation
      |> Map.delete(alias_key)
      |> Map.put("kind", "source_bundle")
      |> Map.put("text", source)
    else
      _not_unambiguous -> operation
    end
  end

  defp joined_source(values) when is_list(values) and values != [] do
    if Enum.all?(values, &source_entry?/1) do
      {:ok, Enum.map_join(values, "\n\n", & &1["source"])}
    else
      :error
    end
  end

  defp joined_source(_values), do: :error

  defp source_entry?(entry) when is_map(entry) do
    source = entry["source"]

    is_binary(source) and byte_size(source) > 0 and
      Enum.all?(Map.keys(entry), &(&1 in ~w(path source))) and
      source_path_matches?(source, entry["path"])
  end

  defp source_entry?(_entry), do: false

  defp source_path_matches?(source, nil) do
    match?({:ok, [_first | _rest]}, SourceBundle.split(source))
  end

  defp source_path_matches?(source, path) when is_binary(path) do
    case SourceBundle.split(source) do
      {:ok, [%{path: ^path}]} -> true
      _other -> false
    end
  end

  defp source_path_matches?(_source, _path), do: false
end
