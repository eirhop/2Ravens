defmodule TwoRavens.Source.Syntax do
  @moduledoc false

  @spec alias_name(Macro.t()) :: {:ok, String.t()} | :error
  def alias_name({:__aliases__, _meta, parts}) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
    else
      :error
    end
  end

  def alias_name(_other), do: :error

  @spec static_aliases(Macro.t(), list()) ::
          {:ok, [{String.t(), String.t()}]} | :error
  def static_aliases(alias_ast, options) when is_list(options) do
    with {:ok, names} <- alias_names(alias_ast),
         true <- Enum.all?(names, &static_alias_name?/1),
         {:ok, as_name} <- alias_as_name(options),
         true <- is_nil(as_name) or length(names) == 1 do
      {:ok,
       Enum.map(names, fn full ->
         short = as_name || full |> String.split(".") |> List.last()
         {short, full}
       end)}
    else
      _unsupported -> :error
    end
  end

  def static_aliases(_alias_ast, _options), do: :error

  defp alias_names({:__aliases__, _meta, _parts} = alias_ast) do
    with {:ok, name} <- alias_name(alias_ast), do: {:ok, [name]}
  end

  defp alias_names({{:., _dot_meta, [base_ast, :{}]}, _meta, suffix_asts})
       when is_list(suffix_asts) do
    with {:ok, base} <- alias_name(base_ast),
         {:ok, suffixes} <- alias_suffixes(suffix_asts) do
      {:ok, Enum.map(suffixes, &"#{base}.#{&1}")}
    end
  end

  defp alias_names(_other), do: :error

  defp alias_suffixes(suffix_asts) do
    suffix_asts
    |> Enum.reduce_while({:ok, []}, fn suffix_ast, {:ok, suffixes} ->
      case alias_name(suffix_ast) do
        {:ok, suffix} -> {:cont, {:ok, [suffix | suffixes]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, suffixes} -> {:ok, Enum.reverse(suffixes)}
      :error -> :error
    end
  end

  defp alias_as_name(options) do
    options = List.flatten(options)

    if Keyword.keyword?(options) do
      options |> Keyword.fetch(:as) |> validate_alias_as_name()
    else
      :error
    end
  end

  defp validate_alias_as_name(:error), do: {:ok, nil}

  defp validate_alias_as_name({:ok, as_ast}) do
    with {:ok, as_name} <- alias_name(as_ast),
         false <- String.contains?(as_name, ".") do
      {:ok, as_name}
    else
      _unsupported -> :error
    end
  end

  defp static_alias_name?(name), do: "__MODULE__" not in String.split(name, ".")

  @spec source_meta(Macro.t()) :: keyword()
  def source_meta({:__aliases__, meta, _parts}), do: meta

  @spec function_head(Macro.t()) :: {atom(), [Macro.t()], Macro.t() | nil}
  def function_head({:when, _meta, [head, guard]}) do
    {name, _meta, args} = head
    {name, args || [], guard}
  end

  def function_head({name, _meta, args}) when is_atom(name), do: {name, args || [], nil}

  @spec block_entries(Macro.t() | nil) :: [Macro.t()]
  def block_entries({:__block__, _meta, entries}), do: entries
  def block_entries(nil), do: []
  def block_entries(entry), do: [entry]

  @spec normalize_ast(Macro.t() | nil) :: String.t() | nil
  def normalize_ast(nil), do: nil
  def normalize_ast(ast), do: Macro.to_string(ast)

  @spec form_name(Macro.t()) :: String.t()
  def form_name({name, _meta, _args}) when is_atom(name), do: Atom.to_string(name)
  def form_name(_other), do: "unknown"
end
