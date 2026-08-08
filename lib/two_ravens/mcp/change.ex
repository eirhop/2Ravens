defmodule TwoRavens.MCP.Change do
  @moduledoc "Decoded-map transport adapter for the `ravens_change` MCP tool."

  alias TwoRavens.Change
  alias TwoRavens.Change.Error
  alias TwoRavens.Change.Receipt
  alias TwoRavens.MCP.ChangeNormalizer

  @doc "Delegates an already decoded JSON request to `TwoRavens.Change`."
  @spec call(map()) :: {:ok, Receipt.t()} | {:error, Error.t()}
  def call(%{"root" => root} = request) when is_binary(root) do
    request = request |> Map.delete("root") |> ChangeNormalizer.normalize()
    Change.submit(root, request)
  end

  def call(_request) do
    {:error, Error.from(%{code: :invalid_arguments, reason: :root_required})}
  end

  @doc false
  def call(root, request) when is_binary(root) and is_map(request),
    do: Change.submit(root, ChangeNormalizer.normalize(request))

  def call(_root, _request), do: {:error, Error.from(%{code: :invalid_arguments})}
end
