defmodule TwoRavens.Change.RequestAttempt do
  @moduledoc "An immutable, bounded version of a decoded change request."

  alias TwoRavens.Repository

  @max_payload_bytes 1_100_000
  @max_stored_bytes 1_200_000
  @retention_seconds 86_400

  @enforce_keys [:id, :version, :payload, :payload_hash, :expires_at, :created_at]
  defstruct [:id, :version, :payload, :payload_hash, :expires_at, :created_at]

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          payload: map(),
          payload_hash: String.t(),
          expires_at: String.t(),
          created_at: String.t()
        }

  @doc false
  @spec new(term()) :: {:ok, t()} | {:error, map()}
  def new(payload) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, encoded} <- encode(payload) do
      {:ok,
       %__MODULE__{
         id: "attempt:a_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false),
         version: 1,
         payload: payload,
         payload_hash: Repository.hash(encoded),
         expires_at: now |> DateTime.add(@retention_seconds, :second) |> DateTime.to_iso8601(),
         created_at: DateTime.to_iso8601(now)
       }}
    end
  end

  @doc false
  @spec next(t(), term()) :: {:ok, t()} | {:error, map()}
  def next(%__MODULE__{} = attempt, payload) do
    with {:ok, encoded} <- encode(payload) do
      {:ok,
       %__MODULE__{
         attempt
         | version: attempt.version + 1,
           payload: payload,
           payload_hash: Repository.hash(encoded),
           created_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
       }}
    end
  end

  @doc false
  @spec encode(term()) :: {:ok, binary()} | {:error, map()}
  def encode(payload) when is_map(payload) do
    with :ok <- validate_json(payload),
         {:ok, encoded} <- Jason.encode(payload),
         :ok <- validate_size(encoded) do
      {:ok, encoded}
    else
      {:error, %Jason.EncodeError{}} ->
        {:error, %{code: :invalid_request_attempt, reason: :json_map_required}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def encode(_payload),
    do: {:error, %{code: :invalid_request_attempt, reason: :json_map_required}}

  @doc false
  @spec load(map(), binary(), binary()) :: {:ok, t()} | {:error, map()}
  def load(payload, expected_hash, encoded) when is_map(payload) and is_binary(encoded) do
    with true <- byte_size(encoded) <= @max_stored_bytes,
         true <- Repository.hash(encoded) == expected_hash,
         {:ok, attempt} <- from_payload(payload) do
      {:ok, attempt}
    else
      _other -> {:error, %{code: :request_attempt_corrupt}}
    end
  end

  def load(_payload, _expected_hash, _encoded),
    do: {:error, %{code: :request_attempt_corrupt}}

  @doc false
  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = attempt) do
    %{
      "id" => attempt.id,
      "version" => attempt.version,
      "request" => attempt.payload,
      "expires_at" => attempt.expires_at,
      "created_at" => attempt.created_at
    }
  end

  @doc false
  @spec encode_storage(t()) :: {:ok, binary()} | {:error, map()}
  def encode_storage(%__MODULE__{} = attempt) do
    payload = dump(attempt)

    with :ok <- validate_json(payload),
         {:ok, encoded} <- Jason.encode(payload),
         true <- byte_size(encoded) <= @max_stored_bytes do
      {:ok, encoded}
    else
      false -> {:error, %{code: :request_attempt_too_large, limit_bytes: @max_payload_bytes}}
      {:error, %Jason.EncodeError{}} -> {:error, %{code: :invalid_request_attempt}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp from_payload(payload) do
    with :ok <- exact_keys(payload),
         id when is_binary(id) and byte_size(id) <= 32 <- payload["id"],
         true <- Regex.match?(~r/^attempt:a_[A-Za-z0-9_-]{12}$/, id),
         version when is_integer(version) and version > 0 <- payload["version"],
         request when is_map(request) <- payload["request"],
         expires_at when is_binary(expires_at) <- payload["expires_at"],
         :ok <- validate_timestamp(expires_at),
         created_at when is_binary(created_at) <- payload["created_at"],
         :ok <- validate_timestamp(created_at),
         {:ok, request_encoded} <- encode(request) do
      {:ok,
       %__MODULE__{
         id: id,
         version: version,
         payload: request,
         payload_hash: Repository.hash(request_encoded),
         expires_at: expires_at,
         created_at: created_at
       }}
    else
      _other -> {:error, %{code: :request_attempt_corrupt}}
    end
  end

  defp exact_keys(payload) do
    if Map.keys(payload) |> Enum.sort() ==
         Enum.sort(~w(id version request expires_at created_at)),
       do: :ok,
       else: {:error, %{code: :request_attempt_corrupt}}
  end

  defp validate_json(value) when is_binary(value) or is_boolean(value) or is_nil(value), do: :ok
  defp validate_json(value) when is_integer(value), do: :ok

  defp validate_json(value) when is_float(value) do
    case Jason.encode(value) do
      {:ok, _encoded} ->
        :ok

      {:error, _reason} ->
        {:error, %{code: :invalid_request_attempt, reason: :json_value_required}}
    end
  end

  defp validate_json(value) when is_list(value) do
    Enum.reduce_while(value, :ok, fn nested, :ok ->
      case validate_json(nested) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_json(value) when is_map(value) do
    Enum.reduce_while(value, :ok, fn
      {key, nested}, :ok when is_binary(key) ->
        case validate_json(nested) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {_key, _nested}, :ok ->
        {:halt, {:error, %{code: :invalid_request_attempt, reason: :string_keys_required}}}
    end)
  end

  defp validate_json(_value),
    do: {:error, %{code: :invalid_request_attempt, reason: :json_value_required}}

  defp validate_size(encoded) do
    if byte_size(encoded) <= @max_payload_bytes,
      do: :ok,
      else: {:error, %{code: :request_attempt_too_large, limit_bytes: @max_payload_bytes}}
  end

  defp validate_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _parsed, 0} -> :ok
      _other -> {:error, %{code: :request_attempt_corrupt}}
    end
  end
end
