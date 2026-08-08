defmodule TwoRavens.Change.RequestPatch do
  @moduledoc false

  alias TwoRavens.Change.RequestAttempt

  @max_operations 100
  @max_patch_bytes 16_384
  @max_path_bytes 1_024

  @spec apply(map(), term()) :: {:ok, map()} | {:error, map()}
  def apply(request, patch) when is_map(request) and is_list(patch) do
    with :ok <- validate_patch_size(patch),
         :ok <- validate_operation_count(patch) do
      patch
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, request}, &apply_indexed_operation/2)
      |> validate_result()
    end
  end

  def apply(_request, _patch),
    do: {:error, %{code: :invalid_request_patch, reason: :non_empty_list_required}}

  defp apply_operation(document, %{"op" => "add", "path" => path, "value" => value} = operation) do
    with :ok <- exact_keys(operation, ~w(op path value)),
         {:ok, segments} <- parse_path(path),
         {:ok, changed} <- add(document, segments, value),
         {:ok, _encoded} <- RequestAttempt.encode(changed) do
      {:ok, changed}
    end
  end

  defp apply_operation(document, %{"op" => "remove", "path" => path} = operation) do
    with :ok <- exact_keys(operation, ~w(op path)),
         {:ok, segments} <- parse_path(path) do
      remove(document, segments)
    end
  end

  defp apply_operation(
         document,
         %{"op" => "replace", "path" => path, "value" => value} = operation
       ) do
    with :ok <- exact_keys(operation, ~w(op path value)),
         {:ok, segments} <- parse_path(path),
         {:ok, changed} <- replace(document, segments, value),
         {:ok, _encoded} <- RequestAttempt.encode(changed) do
      {:ok, changed}
    end
  end

  defp apply_operation(
         document,
         %{"op" => "move", "from" => from, "path" => path} = operation
       ) do
    with :ok <- exact_keys(operation, ~w(op from path)),
         {:ok, from_segments} <- parse_path(from),
         {:ok, path_segments} <- parse_path(path),
         :ok <- reject_descendant_move(from_segments, path_segments),
         {:ok, value} <- fetch(document, from_segments),
         {:ok, removed} <- remove(document, from_segments) do
      add(removed, path_segments, value)
    end
  end

  defp apply_operation(_document, operation) when is_map(operation) do
    {:error,
     %{
       code: :invalid_request_patch,
       reason: :unsupported_operation_shape,
       supported: ~w(add remove replace move)
     }}
  end

  defp apply_operation(_document, _operation),
    do: {:error, %{code: :invalid_request_patch, reason: :operation_map_required}}

  defp apply_indexed_operation({operation, index}, {:ok, current}) do
    case apply_operation(current, operation) do
      {:ok, changed} -> {:cont, {:ok, changed}}
      {:error, reason} -> {:halt, {:error, Map.put(reason, :operation, index)}}
    end
  end

  defp add(document, [key], value) when is_map(document), do: {:ok, Map.put(document, key, value)}

  defp add(document, [index], value) when is_list(document) do
    with {:ok, position} <- insertion_index(index, length(document)) do
      {:ok, List.insert_at(document, position, value)}
    end
  end

  defp add(document, [segment | rest], value) do
    update_child(document, segment, &add(&1, rest, value))
  end

  defp add(_document, _segments, _value), do: path_error(:invalid_add_target)

  defp remove(document, [key]) when is_map(document) do
    if Map.has_key?(document, key),
      do: {:ok, Map.delete(document, key)},
      else: path_error(:path_not_found)
  end

  defp remove(document, [index]) when is_list(document) do
    with {:ok, position} <- existing_index(index, length(document)) do
      {:ok, List.delete_at(document, position)}
    end
  end

  defp remove(document, [segment | rest]) do
    update_child(document, segment, &remove(&1, rest))
  end

  defp remove(_document, _segments), do: path_error(:path_not_found)

  defp replace(document, [key], value) when is_map(document) do
    if Map.has_key?(document, key),
      do: {:ok, Map.put(document, key, value)},
      else: path_error(:path_not_found)
  end

  defp replace(document, [index], value) when is_list(document) do
    with {:ok, position} <- existing_index(index, length(document)) do
      {:ok, List.replace_at(document, position, value)}
    end
  end

  defp replace(document, [segment | rest], value) do
    update_child(document, segment, &replace(&1, rest, value))
  end

  defp replace(_document, _segments, _value), do: path_error(:path_not_found)

  defp fetch(document, [key]) when is_map(document) do
    case Map.fetch(document, key) do
      {:ok, value} -> {:ok, value}
      :error -> path_error(:path_not_found)
    end
  end

  defp fetch(document, [index]) when is_list(document) do
    with {:ok, position} <- existing_index(index, length(document)) do
      {:ok, Enum.at(document, position)}
    end
  end

  defp fetch(document, [segment | rest]) do
    with {:ok, child} <- fetch_child(document, segment), do: fetch(child, rest)
  end

  defp fetch(_document, _segments), do: path_error(:path_not_found)

  defp update_child(document, segment, fun) when is_map(document) do
    with {:ok, child} <- fetch_child(document, segment),
         {:ok, changed} <- fun.(child) do
      {:ok, Map.put(document, segment, changed)}
    end
  end

  defp update_child(document, segment, fun) when is_list(document) do
    with {:ok, position} <- existing_index(segment, length(document)),
         {:ok, changed} <- fun.(Enum.at(document, position)) do
      {:ok, List.replace_at(document, position, changed)}
    end
  end

  defp update_child(_document, _segment, _fun), do: path_error(:path_not_found)

  defp fetch_child(document, key) when is_map(document) do
    case Map.fetch(document, key) do
      {:ok, child} -> {:ok, child}
      :error -> path_error(:path_not_found)
    end
  end

  defp fetch_child(document, index) when is_list(document) do
    with {:ok, position} <- existing_index(index, length(document)) do
      {:ok, Enum.at(document, position)}
    end
  end

  defp fetch_child(_document, _segment), do: path_error(:path_not_found)

  defp parse_path(path) when is_binary(path) and byte_size(path) <= @max_path_bytes do
    case path do
      "" ->
        {:error, %{code: :invalid_request_patch, reason: :root_path_not_supported}}

      "/" <> pointer ->
        pointer
        |> String.split("/", trim: false)
        |> decode_segments()

      _other ->
        {:error, %{code: :invalid_request_patch, reason: :invalid_json_pointer}}
    end
  end

  defp parse_path(_path),
    do: {:error, %{code: :invalid_request_patch, reason: :invalid_json_pointer}}

  defp decode_segment(segment) do
    if Regex.match?(~r/~(?:[^01]|$)/, segment) do
      {:error, %{code: :invalid_request_patch, reason: :invalid_json_pointer_escape}}
    else
      {:ok, segment |> String.replace("~1", "/") |> String.replace("~0", "~")}
    end
  end

  defp decode_segments(segments) do
    segments
    |> Enum.reduce_while({:ok, []}, &decode_next_segment/2)
    |> reverse_decoded_segments()
  end

  defp decode_next_segment(segment, {:ok, decoded}) do
    case decode_segment(segment) do
      {:ok, value} -> {:cont, {:ok, [value | decoded]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reverse_decoded_segments({:ok, decoded}), do: {:ok, Enum.reverse(decoded)}
  defp reverse_decoded_segments(error), do: error

  defp insertion_index("-", length), do: {:ok, length}

  defp insertion_index(index, length) do
    with {:ok, parsed} <- parse_index(index),
         true <- parsed <= length do
      {:ok, parsed}
    else
      _other -> path_error(:invalid_array_index)
    end
  end

  defp existing_index(index, length) do
    with {:ok, parsed} <- parse_index(index),
         true <- parsed < length do
      {:ok, parsed}
    else
      _other -> path_error(:invalid_array_index)
    end
  end

  defp parse_index("0"), do: {:ok, 0}

  defp parse_index(index) when is_binary(index) do
    if Regex.match?(~r/^[1-9][0-9]*$/, index),
      do: {:ok, String.to_integer(index)},
      else: path_error(:invalid_array_index)
  end

  defp exact_keys(operation, expected) do
    if Map.keys(operation) |> Enum.sort() == Enum.sort(expected),
      do: :ok,
      else: {:error, %{code: :invalid_request_patch, reason: :unknown_operation_fields}}
  end

  defp reject_descendant_move(from, destination) do
    if length(destination) > length(from) and Enum.take(destination, length(from)) == from,
      do: {:error, %{code: :invalid_request_patch, reason: :move_into_descendant}},
      else: :ok
  end

  defp validate_patch_size(patch) do
    case Jason.encode(patch) do
      {:ok, encoded} when byte_size(encoded) <= @max_patch_bytes ->
        :ok

      {:ok, _encoded} ->
        {:error, %{code: :request_patch_too_large, limit_bytes: @max_patch_bytes}}

      {:error, _reason} ->
        {:error, %{code: :invalid_request_patch, reason: :json_required}}
    end
  end

  defp validate_operation_count(patch) when length(patch) in 1..@max_operations, do: :ok

  defp validate_operation_count(_patch),
    do: {:error, %{code: :invalid_request_patch, reason: :non_empty_bounded_list_required}}

  defp validate_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp validate_result({:ok, _result}), do: {:error, %{code: :invalid_request_patch_result}}
  defp validate_result(error), do: error

  defp path_error(reason), do: {:error, %{code: :invalid_request_patch, reason: reason}}
end
