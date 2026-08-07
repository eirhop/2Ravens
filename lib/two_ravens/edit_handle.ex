defmodule TwoRavens.EditHandle do
  @moduledoc "Stateless, opaque handles bound to one managed comparison revision."

  alias TwoRavens.Source.Comparison

  @prefix "rv1_"
  @version 1

  @doc "Encodes a comparison target without persistent alias state."
  @spec encode(String.t(), Comparison.t()) :: String.t()
  def encode(file_hash, %Comparison{} = comparison) do
    [
      Integer.to_string(@version),
      comparison.source.path,
      file_hash,
      comparison.function_id,
      comparison.clause_fingerprint,
      comparison.fingerprint,
      "operator"
    ]
    |> Enum.join(<<0>>)
    |> Base.url_encode64(padding: false)
    |> then(&(@prefix <> &1))
  end

  @doc "Decodes and structurally validates a handle."
  @spec decode(String.t()) :: {:ok, map()} | {:error, map()}
  def decode(@prefix <> encoded) when byte_size(encoded) <= 512 do
    with {:ok, binary} <- Base.url_decode64(encoded, padding: false),
         [
           "1",
           path,
           file_hash,
           function_id,
           clause_fingerprint,
           expression_fingerprint,
           "operator"
         ] <- String.split(binary, <<0>>),
         true <-
           valid_payload?(
             path,
             file_hash,
             function_id,
             clause_fingerprint,
             expression_fingerprint
           ) do
      {:ok,
       %{
         version: @version,
         path: path,
         file_hash: file_hash,
         function_id: function_id,
         clause_fingerprint: clause_fingerprint,
         expression_fingerprint: expression_fingerprint,
         property: "operator"
       }}
    else
      _ -> {:error, %{code: :invalid_handle}}
    end
  end

  def decode(_handle), do: {:error, %{code: :invalid_handle}}

  defp valid_payload?(path, file_hash, function_id, clause_fingerprint, expression_fingerprint) do
    path != "" and byte_size(file_hash) == 64 and String.starts_with?(function_id, "function:") and
      byte_size(clause_fingerprint) == 16 and byte_size(expression_fingerprint) == 16
  end
end
