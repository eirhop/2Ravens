defmodule TwoRavens.MCP.Metrics do
  @moduledoc false

  alias TwoRavens.MCP.JSON
  alias TwoRavens.Repository

  @environment "TWO_RAVENS_METRICS_FILE"
  @seen_key {__MODULE__, :seen_source_hashes}

  @doc false
  def record(tool, arguments, result, elapsed_ms)
      when is_binary(tool) and is_map(arguments) and is_integer(elapsed_ms) do
    case System.get_env(@environment) do
      path when is_binary(path) and path != "" ->
        write(path, event(tool, arguments, result, elapsed_ms))

      _unset ->
        :ok
    end
  rescue
    _error -> :ok
  end

  defp event(tool, arguments, result, elapsed_ms) do
    sources = source_values(arguments)

    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      tool: tool,
      request_bytes: encoded_size(arguments),
      response_bytes: encoded_size(result),
      source_bytes: Enum.sum(Enum.map(sources, &byte_size/1)),
      repeated_source_bytes: repeated_source_bytes(sources),
      operation_count: operation_count(tool, arguments),
      selector_count: selector_count(arguments),
      selector_correction_count: code_count(result, :unsupported_selector_includes),
      selector_omission_count: true_key_count(result, :omitted),
      request_repair_count: if(tool == "ravens_retry", do: 1, else: 0),
      draft_repair_count: if(has_key?(arguments, "draft"), do: 1, else: 0),
      retained_attempt_count: if(has_key_deep?(result, :attempt), do: 1, else: 0),
      qualification_count: qualification_count(result),
      elapsed_ms: elapsed_ms,
      outcome: outcome(result)
    }
  end

  defp write(path, event) do
    if Path.type(path) == :absolute do
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, Jason.encode!(event) <> "\n", [:append])
    else
      :ok
    end
  end

  defp source_values(value) when is_map(value) do
    Enum.flat_map(value, fn
      {key, source} when key in ["text", :text, "source", :source] and is_binary(source) ->
        [source]

      {_key, nested} ->
        source_values(nested)
    end)
  end

  defp source_values(value) when is_list(value), do: Enum.flat_map(value, &source_values/1)
  defp source_values(_value), do: []

  defp repeated_source_bytes(sources) do
    seen = Process.get(@seen_key, MapSet.new())

    {repeated, updated} =
      Enum.reduce(sources, {0, seen}, fn source, {bytes, hashes} ->
        hash = Repository.hash(source)

        if MapSet.member?(hashes, hash) do
          {bytes + byte_size(source), hashes}
        else
          {bytes, MapSet.put(hashes, hash)}
        end
      end)

    Process.put(@seen_key, updated)
    repeated
  end

  defp selector_count(arguments) do
    list_length(Map.get(arguments, "select", [])) + list_length(Map.get(arguments, "return", []))
  end

  defp operation_count("ravens_create_bundle", _arguments), do: 1

  defp operation_count("ravens_retry", arguments),
    do: arguments |> Map.get("patch", []) |> list_length()

  defp operation_count(_tool, arguments),
    do: arguments |> Map.get("operations", []) |> list_length()

  defp qualification_count({:ok, %{qualification: qualification}}) when not is_nil(qualification),
    do: 1

  defp qualification_count(_result), do: 0

  defp outcome({:ok, %{status: status}}), do: %{status: status}
  defp outcome({:ok, _value}), do: %{status: :ok}

  defp outcome({:error, %{code: code}} = result) do
    normalized = JSON.normalize(result)
    %{status: :error, code: code, error_bytes: encoded_size(normalized)}
  end

  defp outcome({:error, _reason}), do: %{status: :error}
  defp outcome({:rpc_error, code, _message}), do: %{status: :rpc_error, code: code}

  defp encoded_size(value), do: value |> JSON.normalize() |> Jason.encode!() |> byte_size()
  defp list_length(value) when is_list(value), do: length(value)
  defp list_length(_value), do: 0

  defp code_count(value, code) when is_map(value) do
    own =
      if Map.get(value, :code) == code or Map.get(value, "code") == Atom.to_string(code),
        do: 1,
        else: 0

    own + Enum.sum(Enum.map(Map.values(value), &code_count(&1, code)))
  end

  defp code_count(value, code) when is_list(value),
    do: Enum.sum(Enum.map(value, &code_count(&1, code)))

  defp code_count(value, code) when is_tuple(value),
    do: value |> Tuple.to_list() |> code_count(code)

  defp code_count(_value, _code), do: 0

  defp true_key_count(value, key) when is_map(value) do
    own =
      if Map.get(value, key) == true or Map.get(value, Atom.to_string(key)) == true,
        do: 1,
        else: 0

    own + Enum.sum(Enum.map(Map.values(value), &true_key_count(&1, key)))
  end

  defp true_key_count(value, key) when is_list(value),
    do: Enum.sum(Enum.map(value, &true_key_count(&1, key)))

  defp true_key_count(value, key) when is_tuple(value),
    do: value |> Tuple.to_list() |> true_key_count(key)

  defp true_key_count(_value, _key), do: 0

  defp has_key_deep?(value, key) when is_map(value) do
    has_key?(value, key) or Enum.any?(Map.values(value), &has_key_deep?(&1, key))
  end

  defp has_key_deep?(value, key) when is_list(value),
    do: Enum.any?(value, &has_key_deep?(&1, key))

  defp has_key_deep?(value, key) when is_tuple(value),
    do: value |> Tuple.to_list() |> has_key_deep?(key)

  defp has_key_deep?(_value, _key), do: false

  defp has_key?(map, key) when is_atom(key),
    do: Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))

  defp has_key?(map, key) when is_binary(key), do: Map.has_key?(map, key)
end
