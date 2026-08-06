defmodule RavensBenchmark.Discount do
  @moduledoc """
  Calculates deterministic checkout discounts from customer tier and subtotal.
  """

  @vip_threshold 5_000

  @doc """
  Returns the discount in cents for a subtotal and customer tier.
  """
  @spec amount(non_neg_integer(), RavensBenchmark.Order.customer_tier()) :: non_neg_integer()
  def amount(subtotal, :vip) when subtotal >= @vip_threshold, do: div(subtotal * 10, 100)
  def amount(subtotal, :vip) when subtotal >= 0, do: div(subtotal * 5, 100)
  def amount(subtotal, :standard) when subtotal >= 0, do: 0
end
