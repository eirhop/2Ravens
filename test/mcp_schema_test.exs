defmodule TwoRavens.MCPSchemaTest do
  use ExUnit.Case, async: true

  alias TwoRavens.MCP.Schema

  @combinators ~w(oneOf anyOf allOf not)a

  test "agent-facing schemas are flat, bounded, and expose concrete fields" do
    tools = Schema.tools()

    assert Enum.map(tools, & &1.name) == [
             "ravens_discover",
             "ravens_context",
             "ravens_create_bundle",
             "ravens_change",
             "ravens_retry"
           ]

    assert Enum.all?(tools, &(combinators(&1.inputSchema) == []))

    create = tool(tools, "ravens_create_bundle").inputSchema
    assert create.required == ~w(mode text)
    assert Map.has_key?(create.properties, :text)
    refute Map.has_key?(create.properties, :operations)

    change = tool(tools, "ravens_change").inputSchema
    operation = change.properties.operations.items

    assert change.required == ["mode"]
    assert operation.properties.op.enum == ~w(create replace patch set delete rename move)
    assert operation.properties.kind.enum == ~w(source_bundle function clause module_form)

    assert Enum.all?(~w(parent target text diff handle value cascade to before after), fn field ->
             Map.has_key?(operation.properties, String.to_atom(field))
           end)

    retry = tool(tools, "ravens_retry").inputSchema
    assert retry.required == ~w(attempt attempt_version patch)
    assert retry.properties.patch.items.properties.op.enum == ~w(add remove replace move)

    assert byte_size(Jason.encode!(tools)) < 8_000
  end

  test "real STDIO tools/list advertises the same flat schemas" do
    port = start_server()

    request = Jason.encode!(%{jsonrpc: "2.0", id: 31, method: "tools/list", params: %{}})
    true = Port.command(port, request <> "\n")

    output = receive_line(port, "")
    Port.close(port)

    assert {:ok, %{"result" => %{"tools" => tools}}} = Jason.decode(String.trim(output))

    assert Enum.map(tools, & &1["name"]) == [
             "ravens_discover",
             "ravens_context",
             "ravens_create_bundle",
             "ravens_change",
             "ravens_retry"
           ]

    assert Enum.all?(tools, &(combinators(&1["inputSchema"]) == []))

    assert %{
             "properties" => %{
               "mode" => %{"enum" => ["apply_if_valid", "draft_only"]},
               "text" => %{"maxLength" => 1_000_000}
             },
             "required" => ["mode", "text"]
           } = Enum.find(tools, &(&1["name"] == "ravens_create_bundle"))["inputSchema"]
  end

  defp tool(tools, name), do: Enum.find(tools, &(&1.name == name))

  defp combinators(value) when is_map(value) do
    own = Enum.filter(Map.keys(value), &(key_atom(&1) in @combinators))
    own ++ Enum.flat_map(Map.values(value), &combinators/1)
  end

  defp combinators(value) when is_list(value), do: Enum.flat_map(value, &combinators/1)
  defp combinators(_value), do: []

  defp key_atom(value) when is_atom(value), do: value
  defp key_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp start_server do
    executable = System.find_executable("elixir")

    Port.open({:spawn_executable, String.to_charlist(executable)}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, ["-S", "mix", "ravens.mcp", "--root", File.cwd!()]},
      {:cd, File.cwd!()}
    ])
  end

  defp receive_line(port, buffer) do
    case String.split(buffer, "\n", parts: 2) do
      [line, _rest] when line != "" ->
        line

      _incomplete ->
        receive do
          {^port, {:data, data}} -> receive_line(port, buffer <> data)
        after
          10_000 -> flunk("timed out waiting for MCP tools/list response")
        end
    end
  end
end
