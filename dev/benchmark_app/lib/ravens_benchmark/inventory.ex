defmodule RavensBenchmark.Inventory do
  @moduledoc """
  A small inventory process used to benchmark static OTP message resolution.
  """

  use GenServer

  alias RavensBenchmark.Order

  @type stock :: %{optional(atom()) => non_neg_integer()}
  @type reservation :: %{order_id: String.t(), reserved: %{atom() => pos_integer()}}

  @doc """
  Starts the registered inventory process with the supplied stock.
  """
  @spec start_link(stock()) :: GenServer.on_start()
  def start_link(stock) do
    GenServer.start_link(__MODULE__, stock, name: __MODULE__)
  end

  @doc """
  Attempts to reserve every order item through the inventory process.
  """
  @spec reserve(String.t(), [Order.item()]) ::
          {:ok, reservation()} | {:error, :out_of_stock}
  def reserve(order_id, items) do
    quantities = Map.new(items, &{&1.sku, &1.quantity})
    GenServer.call(__MODULE__, {:reserve, order_id, quantities})
  end

  @impl true
  def init(stock), do: {:ok, stock}

  @impl true
  def handle_call({:reserve, order_id, quantities}, _from, stock) do
    if available?(stock, quantities) do
      updated_stock = decrement(stock, quantities)
      reservation = %{order_id: order_id, reserved: quantities}

      {:reply, {:ok, reservation}, updated_stock}
    else
      {:reply, {:error, :out_of_stock}, stock}
    end
  end

  defp available?(stock, quantities) do
    Enum.all?(quantities, fn {sku, requested} -> Map.get(stock, sku, 0) >= requested end)
  end

  defp decrement(stock, quantities) do
    Enum.reduce(quantities, stock, fn {sku, reserved}, remaining ->
      Map.update!(remaining, sku, &(&1 - reserved))
    end)
  end
end
