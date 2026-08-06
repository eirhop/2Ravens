defmodule RavensBenchmark.CheckoutTest do
  use ExUnit.Case, async: false

  alias RavensBenchmark.Checkout
  alias RavensBenchmark.Inventory
  alias RavensBenchmark.Order

  setup do
    start_supervised!({Inventory, %{book: 3, pen: 10}})
    :ok
  end

  test "places a VIP order through pricing, inventory, and payment" do
    order = %Order{
      id: "order-123",
      customer_tier: :vip,
      items: [%{sku: :book, quantity: 1, unit_price: 6_000}]
    }

    assert {:ok, %{order_id: "order-123", total: 5_400}} = Checkout.place(order)
    assert %{book: 2, pen: 10} = :sys.get_state(Inventory)
  end

  test "returns the inventory failure without charging" do
    order = %Order{
      id: "order-456",
      customer_tier: :standard,
      items: [%{sku: :book, quantity: 4, unit_price: 1_000}]
    }

    assert {:error, :out_of_stock} = Checkout.place(order)
    assert %{book: 3, pen: 10} = :sys.get_state(Inventory)
  end

  test "retains reserved inventory when payment declines" do
    order = %Order{
      id: "order-declined",
      customer_tier: :standard,
      items: [%{sku: :pen, quantity: 10, unit_price: 3_000}]
    }

    assert {:error, :declined} = Checkout.place(order)
    assert %{book: 3, pen: 0} = :sys.get_state(Inventory)
  end

  test "previews an order through the shared pricing path" do
    order = %Order{
      id: "order-789",
      customer_tier: :vip,
      items: [%{sku: :pen, quantity: 2, unit_price: 1_000}]
    }

    assert {:ok, 1_900} = Checkout.preview(order)
    assert %{book: 3, pen: 10} = :sys.get_state(Inventory)
  end

  test "rejects an empty order at the entry point" do
    order = %Order{id: "order-empty", customer_tier: :standard, items: []}

    assert {:error, :empty_order} = Checkout.place(order)
  end
end
