defmodule TwoRavens.Change.Request do
  @moduledoc false

  alias TwoRavens.Change.Operation
  alias TwoRavens.Change.ReturnSelector
  alias TwoRavens.Repository

  @keys ~w(base_revision mode operations draft draft_version request_id return)
  @max_operations 100
  @max_source_bytes 1_000_000

  @spec validate(term()) :: {:ok, map()} | {:error, map()}
  def validate(request) when is_map(request) do
    with :ok <- validate_keys(request),
         {:ok, mode} <- validate_mode(request),
         {:ok, request_id} <- validate_request_id(Map.get(request, "request_id")),
         {:ok, returns} <- ReturnSelector.validate(Map.get(request, "return")),
         {:ok, base} <- validate_base(request),
         {:ok, operations} <- validate_operations(request, mode, base),
         :ok <- validate_source_size(operations),
         :ok <- validate_unchanged_draft_apply(mode, base, operations) do
      validated = %{
        mode: mode,
        operations: operations,
        base: base,
        returns: returns,
        request_id: request_id
      }

      {:ok, Map.put(validated, :request_hash, request_hash(validated))}
    end
  end

  def validate(_request), do: {:error, %{code: :invalid_request, reason: :map_required}}

  defp validate_keys(request) do
    unknown = request |> Map.keys() |> Enum.reject(&(&1 in @keys)) |> Enum.sort()

    cond do
      Enum.any?(Map.keys(request), &(not is_binary(&1))) ->
        {:error, %{code: :invalid_request, reason: :string_keys_required}}

      unknown != [] ->
        {:error, %{code: :unknown_request_fields, fields: unknown}}

      true ->
        :ok
    end
  end

  defp validate_mode(request) do
    case Map.get(request, "mode") do
      "apply_if_valid" -> {:ok, :apply_if_valid}
      "draft_only" -> {:ok, :draft_only}
      nil -> {:error, %{code: :mode_required, supported: ~w(apply_if_valid draft_only)}}
      value -> {:error, %{code: :invalid_mode, value: value}}
    end
  end

  defp validate_request_id(nil), do: {:ok, nil}

  defp validate_request_id(request_id)
       when is_binary(request_id) and byte_size(request_id) in 1..128 do
    if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/, request_id),
      do: {:ok, request_id},
      else: {:error, %{code: :invalid_request_id}}
  end

  defp validate_request_id(_request_id), do: {:error, %{code: :invalid_request_id}}

  defp request_hash(%{request_id: nil}), do: nil

  defp request_hash(validated) do
    validated
    |> Map.drop([:request_id, :request_hash])
    |> :erlang.term_to_binary([:deterministic])
    |> Repository.hash()
  end

  defp validate_operations(%{"operations" => operations}, _mode, _base)
       when is_list(operations) and operations != [] and length(operations) <= @max_operations do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {operation, index}, {:ok, accepted} ->
      case Operation.validate(operation, index) do
        {:ok, validated} -> {:cont, {:ok, [validated | accepted]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, accepted} -> {:ok, Enum.reverse(accepted)}
      error -> error
    end
  end

  defp validate_operations(request, :apply_if_valid, {:draft, _id, _version})
       when not is_map_key(request, "operations"),
       do: {:ok, []}

  defp validate_operations(%{"operations" => operations}, _mode, _base)
       when is_list(operations),
       do: {:error, %{code: :invalid_operations, reason: :non_empty_bounded_list_required}}

  defp validate_operations(_request, _mode, _base),
    do: {:error, %{code: :invalid_operations, reason: :list_required}}

  defp validate_unchanged_draft_apply(:apply_if_valid, {:draft, _id, _version}, []), do: :ok
  defp validate_unchanged_draft_apply(_mode, _base, _operations), do: :ok

  defp validate_source_size(operations) do
    bytes =
      Enum.reduce(operations, 0, fn operation, total ->
        total + byte_size(Map.get(operation, "text", "")) +
          byte_size(Map.get(operation, "diff", ""))
      end)

    if bytes <= @max_source_bytes,
      do: :ok,
      else: {:error, %{code: :request_too_large, limit_bytes: @max_source_bytes}}
  end

  defp validate_base(%{"draft" => draft, "draft_version" => version} = request)
       when is_binary(draft) and byte_size(draft) > 0 and is_integer(version) and version > 0 do
    if Map.has_key?(request, "base_revision"),
      do: {:error, %{code: :conflicting_request_base}},
      else: {:ok, {:draft, draft, version}}
  end

  defp validate_base(%{"base_revision" => revision})
       when is_binary(revision) and byte_size(revision) > 0,
       do: {:ok, {:revision, revision}}

  defp validate_base(request) do
    if Map.has_key?(request, "draft") or Map.has_key?(request, "draft_version"),
      do: {:error, %{code: :invalid_draft_reference}},
      else: {:ok, :empty_project}
  end
end
