defmodule TwoRavens.MCP.Discovery do
  @moduledoc "Decoded-map adapter for the `ravens_discover` MCP tool."

  alias TwoRavens.Discovery

  @doc false
  def call(root, request) when is_binary(root) and is_map(request),
    do: Discovery.query(root, request)

  def call(_root, _request), do: {:error, %{code: :invalid_arguments}}
end
