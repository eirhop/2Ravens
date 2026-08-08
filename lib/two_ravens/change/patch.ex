defmodule TwoRavens.Change.Patch do
  @moduledoc "Exact, bounded unified-diff application to one entity fragment."

  alias TwoRavens.Repository

  @max_hunks 20

  @doc "Applies exact hunks and rejects stale hashes, missing context, and ambiguous matches."
  @spec apply(String.t(), String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, map()}
  def apply(source, diff, expected_hash \\ nil)
      when is_binary(source) and is_binary(diff) and
             (is_nil(expected_hash) or is_binary(expected_hash)) do
    with :ok <- verify_hash(source, expected_hash),
         {:ok, hunks} <- parse(diff),
         true <- length(hunks) <= @max_hunks do
      apply_hunks(hunks, source)
    else
      false -> {:error, %{code: :patch_too_large, max_hunks: @max_hunks}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_hunks(hunks, source) do
    Enum.reduce_while(hunks, {:ok, source}, fn hunk, {:ok, current} ->
      case apply_hunk(current, hunk) do
        {:ok, changed} -> {:cont, {:ok, changed}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_hash(_source, nil), do: :ok

  defp verify_hash(source, expected) do
    if Repository.hash(source) == expected,
      do: :ok,
      else: {:error, %{code: :stale_entity_hash}}
  end

  defp parse(diff) do
    hunks =
      diff
      |> String.split(~r/^@@.*$/m, trim: true)
      |> Enum.map(&parse_hunk/1)

    if hunks != [] and Enum.all?(hunks, &match?({:ok, _}, &1)),
      do: {:ok, Enum.map(hunks, &elem(&1, 1))},
      else: {:error, %{code: :invalid_patch}}
  end

  defp parse_hunk(text) do
    lines = String.split(text, "\n", trim: false)

    if Enum.all?(lines, &(String.starts_with?(&1, ["+", "-", " "]) or &1 == "")) do
      before =
        lines
        |> Enum.reject(&String.starts_with?(&1, "+"))
        |> Enum.map(&strip_marker/1)
        |> trim_terminal_empty()
        |> Enum.join("\n")

      replacement =
        lines
        |> Enum.reject(&String.starts_with?(&1, "-"))
        |> Enum.map(&strip_marker/1)
        |> trim_terminal_empty()
        |> Enum.join("\n")

      if before == "", do: {:error, :empty_context}, else: {:ok, {before, replacement}}
    else
      {:error, :invalid_lines}
    end
  end

  defp trim_terminal_empty(lines) do
    case List.last(lines) do
      "" -> Enum.drop(lines, -1)
      _other -> lines
    end
  end

  defp strip_marker(""), do: ""
  defp strip_marker(line), do: String.slice(line, 1..-1//1)

  defp apply_hunk(source, {before, replacement}) do
    case :binary.matches(source, before) do
      [{_position, _length}] -> {:ok, String.replace(source, before, replacement, global: false)}
      [] -> {:error, %{code: :patch_context_not_found}}
      _many -> {:error, %{code: :ambiguous_patch_context}}
    end
  end
end
