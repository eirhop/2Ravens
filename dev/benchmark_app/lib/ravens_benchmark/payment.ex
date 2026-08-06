defmodule RavensBenchmark.Payment do
  @moduledoc """
  Resolves the configured payment gateway and marks the external effect boundary.
  """

  alias RavensBenchmark.PaymentGateway.Local

  @gateway Application.compile_env(:ravens_benchmark, :payment_gateway, Local)

  @doc """
  Charges an order through the configured payment gateway.
  """
  @spec charge(String.t(), non_neg_integer()) :: :ok | {:error, :declined}
  def charge(order_id, amount) do
    @gateway.charge(order_id, amount)
  end
end
