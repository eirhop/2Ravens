defmodule RavensBenchmark.InventoryTest do
  use ExUnit.Case, async: false

  alias RavensBenchmark.Inventory

  test "maps a reserve call to the handler and updates process state" do
    start_supervised!({Inventory, %{book: 2}})
    items = [%{sku: :book, quantity: 1, unit_price: 2_000}]

    assert {:ok, %{order_id: "order-123", reserved: %{book: 1}}} =
             Inventory.reserve("order-123", items)

    assert %{book: 1} = :sys.get_state(Inventory)
  end
end
