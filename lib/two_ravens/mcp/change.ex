defmodule TwoRavens.MCP.Change do
  @moduledoc "Decoded-map transport adapter for the future `ravens_change` MCP tool."

  alias TwoRavens.Change
  alias TwoRavens.Change.Error
  alias TwoRavens.Change.Receipt

  @doc "Delegates an already decoded JSON request to `TwoRavens.Change`."
  @spec call(map()) :: {:ok, Receipt.t()} | {:error, Error.t()}
  def call(%{"root" => root} = request) when is_binary(root) do
    Change.submit(root, Map.delete(request, "root"))
  end

  def call(_request) do
    {:error, Error.from(%{code: :invalid_arguments, reason: :root_required})}
  end
end
