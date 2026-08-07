defmodule TwoRavens.Source.Syntax do
  @moduledoc false

  @spec alias_name(Macro.t()) :: {:ok, String.t()} | :error
  def alias_name({:__aliases__, _meta, parts}) do
    {:ok, Enum.map_join(parts, ".", &Atom.to_string/1)}
  end

  def alias_name(_other), do: :error

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
