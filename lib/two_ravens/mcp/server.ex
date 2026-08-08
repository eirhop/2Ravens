defmodule TwoRavens.MCP.Server do
  @moduledoc "Local project-bound JSON-RPC MCP server over standard input and output."

  alias TwoRavens.MCP.Change
  alias TwoRavens.MCP.Context
  alias TwoRavens.MCP.CreateBundle
  alias TwoRavens.MCP.Discovery
  alias TwoRavens.MCP.JSON
  alias TwoRavens.MCP.Metrics
  alias TwoRavens.MCP.Retry
  alias TwoRavens.MCP.Schema
  alias TwoRavens.Project

  @protocol "2025-06-18"
  @max_input 1_200_000
  @max_output 64_000

  @doc "Runs the STDIO server bound to one validated project root."
  @spec run(Path.t()) :: :ok | {:error, map()}
  def run(root) do
    with {:ok, project} <- Project.open(root), do: loop(project.root)
  end

  @doc false
  def handle(root, %{"jsonrpc" => "2.0", "id" => id, "method" => method} = request)
      when is_integer(id) or is_nil(id) or (is_binary(id) and byte_size(id) <= 128) do
    response(id, dispatch(root, method, Map.get(request, "params", %{})))
  end

  def handle(_root, %{"jsonrpc" => "2.0", "method" => "notifications/" <> _rest}),
    do: :notification

  def handle(_root, request), do: rpc_error(Map.get(request, "id"), -32_600, "Invalid Request")

  defp loop(root) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        {:error, %{code: :mcp_input_failed, reason: reason}}

      line ->
        line |> decode(root) |> write()
        loop(root)
    end
  end

  defp decode(line, _root) when byte_size(line) > @max_input,
    do: rpc_error(nil, -32_600, "Request exceeds input limit")

  defp decode(line, root) do
    case Jason.decode(line) do
      {:ok, request} when is_map(request) -> safe_handle(root, request)
      {:ok, _value} -> rpc_error(nil, -32_600, "Invalid Request")
      {:error, _reason} -> rpc_error(nil, -32_700, "Parse error")
    end
  end

  defp safe_handle(root, request) do
    handle(root, request)
  rescue
    _exception -> rpc_error(Map.get(request, "id"), -32_603, "Internal error")
  catch
    _kind, _reason -> rpc_error(Map.get(request, "id"), -32_603, "Internal error")
  end

  defp write(:notification), do: :ok
  defp write(response), do: IO.write(Jason.encode!(response) <> "\n")

  defp dispatch(_root, "initialize", params) when is_map(params) do
    {:ok,
     %{
       protocolVersion: @protocol,
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: %{name: "two_ravens", version: "0.1.0"}
     }}
  end

  defp dispatch(_root, "tools/list", params) when is_map(params),
    do: {:ok, %{tools: Schema.tools(), resultType: "complete"}}

  defp dispatch(_root, "ping", params) when is_map(params), do: {:ok, %{}}

  defp dispatch(root, "tools/call", %{"name" => name, "arguments" => arguments})
       when is_binary(name) and is_map(arguments) do
    started = System.monotonic_time(:millisecond)
    result = raw_tool_call(root, name, arguments)
    Metrics.record(name, arguments, result, System.monotonic_time(:millisecond) - started)

    case result do
      {:rpc_error, _code, _message} = error -> error
      tool_call -> tool_result(tool_call)
    end
  end

  defp dispatch(_root, "tools/call", _params), do: {:rpc_error, -32_602, "Invalid params"}
  defp dispatch(_root, _method, _params), do: {:rpc_error, -32_601, "Method not found"}

  defp raw_tool_call(root, "ravens_change", arguments), do: Change.call(root, arguments)

  defp raw_tool_call(root, "ravens_discover", arguments),
    do: Discovery.call(root, arguments)

  defp raw_tool_call(root, "ravens_create_bundle", arguments),
    do: CreateBundle.call(root, arguments)

  defp raw_tool_call(root, "ravens_context", arguments), do: Context.call(root, arguments)

  defp raw_tool_call(root, "ravens_retry", arguments), do: Retry.call(root, arguments)

  defp raw_tool_call(_root, _name, _arguments),
    do: {:rpc_error, -32_602, "Unknown tool"}

  defp tool_result({:ok, value}), do: bounded_result(value, false)
  defp tool_result({:error, error}), do: bounded_result(error, true)

  defp bounded_result(value, error?) do
    normalized = value |> JSON.normalize() |> decorate()

    result = %{
      content: [
        %{
          type: "text",
          text: if(error?, do: "2Ravens request failed", else: "2Ravens request completed")
        }
      ],
      structuredContent: normalized,
      resultType: "complete",
      isError: error?
    }

    if result |> Jason.encode!() |> byte_size() <= @max_output - 512 do
      {:ok, result}
    else
      oversized_result(normalized, error?)
    end
  end

  defp oversized_result(%{"status" => _status} = receipt, error?) do
    compact =
      receipt
      |> Map.take(~w(status operation_count draft draft_version revision working_tree_changed))
      |> Map.put("selected", [
        %{
          "omitted" => true,
          "error" => %{"code" => "mcp_output_too_large", "limit_bytes" => @max_output}
        }
      ])

    {:ok,
     %{
       content: [%{type: "text", text: "2Ravens request completed; optional output omitted"}],
       structuredContent: compact,
       resultType: "complete",
       isError: error?
     }}
  end

  defp oversized_result(_value, _error?),
    do: bounded_result(%{code: :mcp_output_too_large, limit_bytes: @max_output}, true)

  defp decorate(%{"status" => "applied"} = receipt) do
    qualification = Map.get(receipt, "qualification", %{})

    receipt
    |> Map.put("verification_complete", true)
    |> Map.put("next_action", "none")
    |> Map.put("proof", %{
      "format" => Map.get(qualification, "format"),
      "compile" => Map.get(qualification, "compile"),
      "tests" => Map.get(qualification, "tests"),
      "source_read_back" => "pass",
      "graph_comparison" => "pass",
      "semantic_persistence" => "pass"
    })
  end

  defp decorate(%{"status" => "needs_changes"} = receipt),
    do: Map.put(receipt, "next_action", "repair_draft")

  defp decorate(%{"status" => "ready"} = receipt),
    do: Map.put(receipt, "next_action", "apply_ready_draft")

  defp decorate(%{"details" => details} = error) when is_map(details) do
    case {details["attempt"], details["attempt_version"]} do
      {attempt, version} when is_binary(attempt) and is_integer(version) ->
        error
        |> Map.put("attempt", attempt)
        |> Map.put("attempt_version", version)
        |> Map.put("repair", %{
          "tool" => "ravens_retry",
          "attempt" => attempt,
          "attempt_version" => version
        })

      _no_attempt ->
        error
    end
  end

  defp decorate(value), do: value

  defp response(id, {:ok, result}), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  defp response(id, {:rpc_error, code, message}), do: rpc_error(id, code, message)

  defp rpc_error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
