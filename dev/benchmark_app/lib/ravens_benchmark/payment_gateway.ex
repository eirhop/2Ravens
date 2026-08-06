defmodule RavensBenchmark.PaymentGateway do
  @moduledoc """
  Boundary contract for charging an order through an external payment system.
  """

  @doc """
  Charges an order identifier for an amount in cents.
  """
  @callback charge(String.t(), non_neg_integer()) :: :ok | {:error, :declined}
end
