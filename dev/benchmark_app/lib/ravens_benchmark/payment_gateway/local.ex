defmodule RavensBenchmark.PaymentGateway.Local do
  @moduledoc """
  A deterministic local payment gateway for benchmark execution.
  """

  @behaviour RavensBenchmark.PaymentGateway

  @decline_above 20_000

  @doc """
  Accepts ordinary benchmark charges and declines amounts above the local limit.
  """
  @impl true
  def charge(_order_id, amount) when amount > @decline_above, do: {:error, :declined}
  def charge(_order_id, amount) when amount >= 0, do: :ok
end
