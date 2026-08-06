defmodule RavensBenchmark.Order do
  @moduledoc """
  An order used by the benchmark checkout flow.
  """

  @enforce_keys [:id, :items, :customer_tier]
  defstruct [:id, :items, :customer_tier]

  @type item :: %{
          required(:sku) => atom(),
          required(:quantity) => pos_integer(),
          required(:unit_price) => non_neg_integer()
        }

  @type customer_tier :: :standard | :vip

  @type t :: %__MODULE__{
          id: String.t(),
          items: [item()],
          customer_tier: customer_tier()
        }
end
