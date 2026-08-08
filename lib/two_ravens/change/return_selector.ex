defmodule TwoRavens.Change.ReturnSelector do
  @moduledoc false

  alias TwoRavens.Selector

  @spec validate(term()) :: {:ok, [map()]} | {:error, map()}
  def validate(nil), do: {:ok, []}
  def validate(selectors), do: Selector.validate_strict(selectors)
end
