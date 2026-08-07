defmodule TwoRavens.Source.Range do
  @moduledoc false

  alias TwoRavens.SourceRange

  @spec select(String.t(), SourceRange.t()) :: String.t()
  def select(source, %SourceRange{start_line: first, end_line: last}) do
    source
    |> String.split("\n", trim: false)
    |> Enum.slice((first - 1)..(last - 1))
    |> Enum.join("\n")
  end

  @spec line_of(Macro.t()) :: pos_integer()
  def line_of({_form, meta, _args}), do: meta[:line] || 1

  @spec column_of(Macro.t()) :: pos_integer()
  def column_of({_form, meta, _args}), do: meta[:column] || 1

  @spec final_module_end_line([String.t()]) :: pos_integer()
  def final_module_end_line(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.find_value(1, fn {line, index} -> if String.trim(line) == "end", do: index end)
  end

  @spec line_column([String.t()], pos_integer()) :: pos_integer()
  def line_column(lines, line) do
    lines |> Enum.at(line - 1, "") |> String.length() |> Kernel.+(1)
  end

  @spec ast_end(Macro.t(), [String.t()], pos_integer()) :: {pos_integer(), pos_integer()}
  def ast_end({_form, meta, _args}, lines, fallback_line) do
    end_meta = meta[:end] || meta[:end_of_expression]

    if is_list(end_meta) and is_integer(end_meta[:line]) do
      {end_meta[:line], end_meta[:column] || line_column(lines, end_meta[:line])}
    else
      {fallback_line, line_column(lines, fallback_line)}
    end
  end

  @spec put_start(SourceRange.t(), keyword()) :: SourceRange.t()
  def put_start(range, meta) do
    %{range | start_line: meta[:line] || 1, start_column: meta[:column] || 1}
  end

  @spec token(String.t(), keyword(), non_neg_integer()) :: SourceRange.t()
  def token(path, meta, length) do
    line = meta[:line] || 1
    column = meta[:column] || 1
    new(path, line, column, line, column + length)
  end

  @spec new(String.t(), pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          SourceRange.t()
  def new(path, start_line, start_column, end_line, end_column) do
    %SourceRange{
      path: path,
      start_line: start_line,
      start_column: start_column,
      end_line: end_line,
      end_column: end_column
    }
  end
end
