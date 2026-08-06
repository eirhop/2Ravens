defmodule RavensBenchmark.Checkout do
  @moduledoc """
  Entry points for placing and previewing benchmark orders.
  """

  alias RavensBenchmark.Inventory
  alias RavensBenchmark.Order
  alias RavensBenchmark.Payment
  alias RavensBenchmark.Pricing

  @type receipt :: %{order_id: String.t(), total: non_neg_integer()}

  @doc """
  Calculates a total, reserves inventory, and charges the order.
  """
  @spec place(Order.t()) ::
          {:ok, receipt()}
          | {:error, :empty_order | :out_of_stock | :declined}
  def place(%Order{items: []}), do: {:error, :empty_order}

  def place(%Order{id: order_id, items: items} = order)
      when is_binary(order_id) and is_list(items) do
    with {:ok, total} <- Pricing.total(items, order.customer_tier),
         {:ok, _reservation} <- Inventory.reserve(order_id, items),
         :ok <- Payment.charge(order_id, total) do
      {:ok, %{order_id: order_id, total: total}}
    end
  end

  @doc """
  Calculates the total without reserving inventory or charging the order.
  """
  @spec preview(Order.t()) :: {:ok, non_neg_integer()} | {:error, :empty_order}
  def preview(%Order{} = order) do
    Pricing.total(order.items, order.customer_tier)
  end
end
