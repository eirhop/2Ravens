defmodule TwoRavens.MCP.Retry do
  @moduledoc "Decoded-map adapter for retrying one retained malformed request."

  alias TwoRavens.Change
  alias TwoRavens.Change.Error

  @keys ~w(attempt attempt_version patch)

  @doc false
  def call(
        root,
        %{"attempt" => attempt, "attempt_version" => version, "patch" => patch} = arguments
      )
      when is_binary(root) and is_binary(attempt) and is_integer(version) and version > 0 and
             is_list(patch) do
    with :ok <- validate_keys(arguments) do
      Change.retry(root, attempt, version, patch)
    end
  end

  def call(_root, _arguments), do: {:error, Error.from(%{code: :invalid_arguments})}

  defp validate_keys(arguments) do
    if arguments |> Map.keys() |> Enum.sort() == Enum.sort(@keys),
      do: :ok,
      else: {:error, Error.from(%{code: :unknown_request_fields})}
  end
end
