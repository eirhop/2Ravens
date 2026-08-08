defmodule TwoRavens.Change.Operation do
  @moduledoc false

  @operations ~w(create replace patch set delete rename move)
  @kinds ~w(source_bundle function clause module_form)
  @common ~w(op)

  @spec validate(term(), non_neg_integer()) :: {:ok, map()} | {:error, map()}
  def validate(operation, index) when is_map(operation) do
    with {:ok, op} <- fetch_string(operation, "op"),
         :ok <- member(op, @operations, :unsupported_operation),
         :ok <- validate_keys(operation, allowed_keys(op)),
         :ok <- validate_shape(op, operation) do
      {:ok, operation}
    else
      {:error, reason} -> {:error, Map.put(reason, :operation, index)}
    end
  end

  def validate(_operation, index),
    do: {:error, %{code: :invalid_operation, operation: index, reason: :map_required}}

  defp allowed_keys("create"), do: @common ++ ~w(kind parent text before after)
  defp allowed_keys("replace"), do: @common ++ ~w(target text)
  defp allowed_keys("patch"), do: @common ++ ~w(target diff hash)
  defp allowed_keys("set"), do: @common ++ ~w(handle target field value)
  defp allowed_keys("delete"), do: @common ++ ~w(target cascade)
  defp allowed_keys("rename"), do: @common ++ ~w(target to)
  defp allowed_keys("move"), do: @common ++ ~w(target to before after)

  defp validate_shape("create", operation) do
    with {:ok, kind} <- fetch_string(operation, "kind"),
         :ok <- member(kind, @kinds, :unsupported_entity_kind),
         {:ok, _text} <- fetch_bounded_text(operation, "text"),
         :ok <- validate_create_parent(kind, operation) do
      validate_anchors(operation)
    end
  end

  defp validate_shape(op, operation) when op in ["replace", "patch"] do
    key = if op == "replace", do: "text", else: "diff"

    with {:ok, _target} <- fetch_string(operation, "target"),
         {:ok, _text} <- fetch_bounded_text(operation, key) do
      :ok
    end
  end

  defp validate_shape("set", operation) do
    handle? = is_binary(operation["handle"])
    field? = is_binary(operation["target"]) and is_binary(operation["field"])

    if (handle? or field?) and not (handle? and field?) and Map.has_key?(operation, "value") do
      :ok
    else
      {:error, %{code: :invalid_operation, reason: :set_requires_handle_or_target_field}}
    end
  end

  defp validate_shape("delete", operation) do
    with {:ok, _target} <- fetch_string(operation, "target") do
      case Map.get(operation, "cascade", false) do
        value when is_boolean(value) -> :ok
        _value -> {:error, %{code: :invalid_operation, reason: :boolean_cascade_required}}
      end
    end
  end

  defp validate_shape("rename", operation) do
    with {:ok, _target} <- fetch_string(operation, "target") do
      case fetch_string(operation, "to") do
        {:ok, _to} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_shape("move", operation) do
    with {:ok, _target} <- fetch_string(operation, "target"),
         :ok <- require_destination_or_anchor(operation) do
      validate_anchors(operation)
    end
  end

  defp validate_create_parent("source_bundle", operation) do
    if Map.has_key?(operation, "parent"),
      do: {:error, %{code: :invalid_operation, reason: :source_bundle_has_no_parent}},
      else: :ok
  end

  defp validate_create_parent(_kind, operation) do
    case fetch_string(operation, "parent") do
      {:ok, _parent} -> :ok
      {:error, _reason} -> {:error, %{code: :invalid_operation, reason: :parent_required}}
    end
  end

  defp validate_anchors(operation) do
    if Map.has_key?(operation, "before") and Map.has_key?(operation, "after"),
      do: {:error, %{code: :invalid_operation, reason: :conflicting_anchors}},
      else: :ok
  end

  defp require_destination_or_anchor(operation) do
    if Enum.any?(~w(to before after), &is_binary(operation[&1])),
      do: :ok,
      else: {:error, %{code: :invalid_operation, reason: :move_destination_required}}
  end

  defp validate_keys(map, allowed) do
    unknown = map |> Map.keys() |> Enum.reject(&(&1 in allowed)) |> Enum.sort()

    cond do
      Enum.any?(Map.keys(map), &(not is_binary(&1))) ->
        {:error, %{code: :invalid_operation, reason: :string_keys_required}}

      unknown != [] ->
        {:error, %{code: :unknown_operation_fields, fields: unknown}}

      true ->
        :ok
    end
  end

  defp fetch_string(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _other -> {:error, %{code: :invalid_operation, reason: {:non_empty_string_required, key}}}
    end
  end

  defp fetch_bounded_text(map, key) do
    with {:ok, value} <- fetch_string(map, key) do
      if byte_size(value) <= 1_000_000,
        do: {:ok, value},
        else: {:error, %{code: :request_too_large, field: key}}
    end
  end

  defp member(value, allowed, code) do
    if value in allowed,
      do: :ok,
      else: {:error, %{code: code, value: value, supported: allowed}}
  end
end
