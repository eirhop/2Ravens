defmodule TwoRavens.ManagedPath do
  @moduledoc "A normalized repository-relative path permitted by management metadata."

  @enforce_keys [:relative]
  defstruct [:relative]

  @opaque t :: %__MODULE__{relative: String.t()}

  @doc "Validates and normalizes a managed Elixir source path."
  @spec new(String.t()) :: {:ok, t()} | {:error, map()}
  def new(path) when is_binary(path) do
    normalized = String.replace(path, "\\", "/")
    segments = Path.split(normalized)

    cond do
      path == "" -> error(path)
      String.contains?(path, <<0>>) -> error(path)
      Path.type(normalized) != :relative -> error(path)
      Enum.any?(segments, &(&1 in [".", "..", ""])) -> error(path)
      not String.ends_with?(normalized, [".ex", ".exs"]) -> error(path)
      true -> {:ok, %__MODULE__{relative: Enum.join(segments, "/")}}
    end
  end

  def new(path), do: error(path)

  @doc "Returns the normalized repository-relative string."
  @spec relative(t()) :: String.t()
  def relative(%__MODULE__{relative: relative}), do: relative

  defp error(value), do: {:error, %{code: :invalid_managed_path, value: value}}
end
