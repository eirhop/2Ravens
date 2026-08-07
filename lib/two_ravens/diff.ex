defmodule TwoRavens.Diff do
  @moduledoc "Small deterministic unified diffs for one managed source file."

  @doc "Returns an ordinary unified diff for a before-and-after source pair."
  @spec unified(String.t(), String.t(), String.t()) :: String.t()
  def unified(path, before, changed) when is_binary(path) do
    before_lines = lines(before)
    after_lines = lines(changed)
    prefix = common_prefix(before_lines, after_lines)
    suffix = common_suffix(Enum.drop(before_lines, prefix), Enum.drop(after_lines, prefix))
    removed = Enum.slice(before_lines, prefix, length(before_lines) - prefix - suffix)
    added = Enum.slice(after_lines, prefix, length(after_lines) - prefix - suffix)

    header = ["--- a/#{path}", "+++ b/#{path}"]

    hunk =
      ["@@ -#{prefix + 1},#{length(removed)} +#{prefix + 1},#{length(added)} @@"] ++
        Enum.map(removed, &"-#{&1}") ++ Enum.map(added, &"+#{&1}")

    Enum.join(header ++ hunk, "\n") <> "\n"
  end

  @doc "Counts removed or added line pairs, with a replacement counting once."
  @spec changed_lines(String.t(), String.t()) :: non_neg_integer()
  def changed_lines(before, changed) do
    before_lines = lines(before)
    after_lines = lines(changed)
    prefix = common_prefix(before_lines, after_lines)
    suffix = common_suffix(Enum.drop(before_lines, prefix), Enum.drop(after_lines, prefix))
    removed = length(before_lines) - prefix - suffix
    added = length(after_lines) - prefix - suffix
    max(removed, added)
  end

  defp lines(""), do: []
  defp lines(source), do: String.split(String.trim_trailing(source, "\n"), "\n", trim: false)

  defp common_prefix(left, right) do
    left
    |> Enum.zip(right)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end

  defp common_suffix(left, right) do
    left
    |> Enum.reverse()
    |> common_prefix(Enum.reverse(right))
  end
end
