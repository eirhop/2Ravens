defmodule TwoRavens.MCP.Context do
  @moduledoc "Decoded-map adapter for the `ravens_context` MCP tool."

  alias TwoRavens.Context

  @doc false
  def call(root, request) when is_binary(root) and is_map(request),
    do: Context.batch(root, request)

  def call(_root, _request), do: {:error, %{code: :invalid_arguments}}
end
