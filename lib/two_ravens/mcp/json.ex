defmodule TwoRavens.MCP.JSON do
  @moduledoc false

  def normalize(%_{} = struct), do: struct |> Map.from_struct() |> normalize()

  def normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), normalize(value)} end)

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> normalize()
  def normalize(nil), do: nil
  def normalize(true), do: true
  def normalize(false), do: false
  def normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  def normalize(value), do: value
end
