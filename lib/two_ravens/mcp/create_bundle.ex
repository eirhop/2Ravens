defmodule TwoRavens.MCP.CreateBundle do
  @moduledoc "Flat MCP adapter for creating one or more new Elixir modules."

  alias TwoRavens.Change
  alias TwoRavens.Change.Error

  @keys ~w(base_revision mode request_id return text)

  @doc false
  def call(root, arguments) when is_binary(root) and is_map(arguments) do
    with :ok <- validate_keys(arguments),
         {:ok, request} <- request(root, arguments) do
      Change.submit(root, request)
    end
  end

  def call(_root, _arguments), do: {:error, Error.from(%{code: :invalid_arguments})}

  defp request(root, %{"mode" => mode, "text" => text} = arguments)
       when is_binary(mode) and is_binary(text) and byte_size(text) > 0 do
    with {:ok, revision} <- base_revision(root, arguments) do
      request =
        arguments
        |> Map.take(~w(mode request_id return))
        |> Map.put("base_revision", revision)
        |> Map.put("operations", [
          %{"op" => "create", "kind" => "source_bundle", "text" => text}
        ])

      {:ok, request}
    end
  end

  defp request(_root, _arguments),
    do: {:error, Error.from(%{code: :invalid_arguments, reason: :mode_and_text_required})}

  defp base_revision(_root, %{"base_revision" => revision})
       when is_binary(revision) and byte_size(revision) > 0,
       do: {:ok, revision}

  defp base_revision(root, arguments) do
    if Map.has_key?(arguments, "base_revision") do
      {:error, Error.from(%{code: :invalid_arguments, reason: :invalid_base_revision})}
    else
      Change.current_revision(root)
    end
  end

  defp validate_keys(arguments) do
    unknown = arguments |> Map.keys() |> Enum.reject(&(&1 in @keys)) |> Enum.sort()

    cond do
      Enum.any?(Map.keys(arguments), &(not is_binary(&1))) ->
        {:error, Error.from(%{code: :invalid_arguments, reason: :string_keys_required})}

      unknown != [] ->
        {:error, Error.from(%{code: :unknown_request_fields, fields: unknown})}

      true ->
        :ok
    end
  end
end
