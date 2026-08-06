defmodule RavensBenchmark.Pricing do
  @moduledoc """
  Calculates order totals shared by checkout and preview flows.
  """

  alias RavensBenchmark.Discount
  alias RavensBenchmark.Order

  @doc """
  Calculates an order total in cents after applying the customer discount.
  """
  @spec total([Order.item()], Order.customer_tier()) ::
          {:ok, non_neg_integer()} | {:error, :empty_order}
  def total([], _customer_tier), do: {:error, :empty_order}

  def total(items, customer_tier) when is_list(items) do
    subtotal = Enum.reduce(items, 0, &add_line_total/2)
    discount = Discount.amount(subtotal, customer_tier)

    {:ok, subtotal - discount}
  end

  defp add_line_total(%{quantity: quantity, unit_price: unit_price}, subtotal)
       when quantity > 0 and unit_price >= 0 do
    subtotal + quantity * unit_price
  end
end
