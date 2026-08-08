defmodule TwoRavens.MCPServerProtocolTest do
  use ExUnit.Case, async: true

  alias TwoRavens.MCP.JSON
  alias TwoRavens.MCP.Server

  test "initialize and tools/list expose a JSON-safe project-bound protocol" do
    root = File.cwd!()

    initialized =
      Server.handle(root, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{}
      })

    assert initialized["result"].serverInfo.name == "two_ravens"

    listed =
      Server.handle(root, %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list",
        "params" => %{}
      })

    assert Enum.map(listed["result"].tools, & &1.name) == [
             "ravens_discover",
             "ravens_context",
             "ravens_create_bundle",
             "ravens_change",
             "ravens_retry"
           ]

    assert JSON.normalize(%{null: nil, yes: true, no: false}) == %{
             "null" => nil,
             "yes" => true,
             "no" => false
           }
  end

  test "a real STDIO process answers initialize" do
    executable = System.find_executable("elixir")

    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, ["-S", "mix", "ravens.mcp", "--root", File.cwd!()]},
        {:cd, File.cwd!()}
      ])

    request = Jason.encode!(%{jsonrpc: "2.0", id: 7, method: "initialize", params: %{}})
    true = Port.command(port, request <> "\n")

    assert_receive {^port, {:data, output}}, 10_000
    Port.close(port)

    assert {:ok, %{"id" => 7, "result" => %{"serverInfo" => %{"name" => "two_ravens"}}}} =
             Jason.decode(String.trim(output))
  end
end

defmodule TwoRavens.MCPServerIntegrationTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring
  alias TwoRavens.MCP.Server

  @moduletag timeout: 300_000

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-mcp-#{System.unique_integer([:positive])}")
    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(mix, ["new", root, "--app", "mcp_shop"], stderr_to_stdout: true)

    assert {:ok, _manifest} = Authoring.init(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "change return, batched context, retained draft, and malformed selection isolation", %{
    root: root
  } do
    source = """
    defmodule McpShop.Pricing do
      @moduledoc "Prices orders."
      alias String, as: Text

      @doc "Returns the total."
      def total(quantity, price), do: quantity * price
      def fee(total), do: div(total, 100)
      def label, do: Text.upcase("price")
    end
    """

    created =
      call(root, 1, "ravens_create_bundle", %{
        "mode" => "apply_if_valid",
        "text" => source,
        "return" => [
          %{"focus" => "function:McpShop.Pricing.total/2", "include" => ["source"]},
          %{"focus" => "function:McpShop.Pricing.fee/1", "include" => ["source"]},
          %{
            "focus" => "module:McpShop.Pricing",
            "include" => ["functions", "source", "callees"]
          },
          %{"focus" => "function:McpShop.Pricing.missing/0", "include" => ["source"]}
        ]
      })

    refute created.isError
    assert created.structuredContent["status"] == "applied"
    assert created.structuredContent["verification_complete"]
    assert created.structuredContent["next_action"] == "none"

    assert [
             %{"source" => function_source},
             %{"source" => fee_source},
             %{
               "functions" => inventory,
               "warnings" => [%{"code" => "unsupported_selector_includes"}]
             },
             %{"omitted" => true, "error" => %{"code" => "selector_target_not_found"}}
           ] = created.structuredContent["selected"]

    assert function_source =~ "def total"
    assert fee_source =~ "def fee"
    assert Enum.all?(inventory, &String.starts_with?(&1["focus"], "function:McpShop.Pricing."))

    discovery = call(root, 30, "ravens_discover", %{"query" => "pricing", "limit" => 100})

    refute discovery.isError
    assert discovery.structuredContent["base_revision"] == created.structuredContent["revision"]

    assert discovery.structuredContent["warnings"] == [
             %{"code" => "discovery_limit_clamped", "requested" => 100, "applied" => 20}
           ]

    assert [%{"focus" => "module:McpShop.Pricing"} = pricing] =
             discovery.structuredContent["results"]

    assert pricing["path"] == "lib/mcp_shop/pricing.ex"
    assert pricing["doc"] == "Prices orders."

    assert Enum.any?(pricing["public_functions"], fn function ->
             function["focus"] == "function:McpShop.Pricing.total/2" and
               function["doc"] == "Returns the total."
           end)

    context =
      call(root, 2, "ravens_context", %{
        "select" => [
          %{
            "focus" => "function:McpShop.Pricing.total/2",
            "include" => ["source", "callers", "callees"]
          },
          %{"focus" => "function:McpShop.Pricing.fee/1", "include" => ["source"]},
          %{"focus" => "module:McpShop.Pricing", "include" => ["functions"]}
        ]
      })

    refute context.isError
    assert is_binary(context.structuredContent["base_revision"])

    assert [%{"source" => ^function_source}, %{"source" => ^fee_source}, %{"functions" => _}] =
             context.structuredContent["results"]

    tolerant =
      call(root, 32, "ravens_context", %{
        "select" => [
          %{
            "focus" => "module:McpShop.Pricing",
            "include" => ["functions", "source", "callees"]
          },
          %{"focus" => "function:McpShop.Pricing.fee/1", "include" => ["source"]}
        ]
      })

    refute tolerant.isError

    assert [
             %{"functions" => _, "warnings" => [%{"code" => "unsupported_selector_includes"}]},
             %{"source" => ^fee_source}
           ] = tolerant.structuredContent["results"]

    form_context =
      call(root, 20, "ravens_context", %{
        "select" => [%{"focus" => "module:McpShop.Pricing", "include" => ["forms"]}]
      })

    assert [%{"forms" => forms}] = form_context.structuredContent["results"]

    assert %{"focus" => "module_form:" <> _, "source" => alias_source} =
             Enum.find(forms, &String.starts_with?(&1["source"], "alias String"))

    assert alias_source =~ "as: Text"

    rejected_module_patch =
      call(root, 21, "ravens_change", %{
        "base_revision" => context.structuredContent["base_revision"],
        "mode" => "apply_if_valid",
        "operations" => [
          %{
            "op" => "patch",
            "target" => "module:McpShop.Pricing",
            "diff" => "@@\n-  alias String, as: Text\n+  alias String"
          }
        ]
      })

    assert rejected_module_patch.isError
    assert rejected_module_patch.structuredContent["code"] == "whole_module_patch_not_allowed"

    still_alive =
      call(root, 22, "ravens_context", %{
        "select" => [%{"focus" => "module:McpShop.Pricing", "include" => ["functions"]}]
      })

    refute still_alive.isError

    assert_stdio_round_trip(root)

    path = Path.join(root, "lib/mcp_shop/pricing.ex")
    before = File.read!(path)

    malformed =
      call(root, 3, "ravens_change", %{
        "base_revision" => context.structuredContent["base_revision"],
        "mode" => "apply_if_valid",
        "operations" => [%{"op" => "delete", "target" => "function:McpShop.Pricing.total/2"}],
        "return" => [%{"focus" => "module:McpShop.Pricing", "include" => ["source"]}]
      })

    assert malformed.isError
    assert File.read!(path) == before

    failed =
      call(root, 4, "ravens_change", %{
        "base_revision" => context.structuredContent["base_revision"],
        "mode" => "apply_if_valid",
        "operations" => [
          %{
            "op" => "create",
            "kind" => "function",
            "parent" => "module:McpShop.Pricing",
            "text" => "def broken, do: missing_local()"
          }
        ],
        "return" => [%{"focus" => "function:McpShop.Pricing.broken/0", "include" => ["source"]}]
      })

    refute failed.isError
    assert failed.structuredContent["status"] == "needs_changes"
    assert [%{"source" => broken}] = failed.structuredContent["selected"]
    assert broken =~ "missing_local"
    assert File.read!(path) == before

    huge_doc = String.duplicate("x", 33_000)

    oversized =
      call(root, 5, "ravens_change", %{
        "base_revision" => context.structuredContent["base_revision"],
        "mode" => "apply_if_valid",
        "operations" => [
          %{
            "op" => "create",
            "kind" => "function",
            "parent" => "module:McpShop.Pricing",
            "text" => "@doc \"#{huge_doc}\"\ndef huge, do: :ok"
          }
        ],
        "return" => [
          %{"focus" => "function:McpShop.Pricing.huge/0", "include" => ["source"]},
          %{"focus" => "module:McpShop.Pricing", "include" => ["functions"]}
        ]
      })

    refute oversized.isError
    assert oversized.structuredContent["status"] == "applied"
    assert oversized.structuredContent["working_tree_changed"]
    assert is_binary(oversized.structuredContent["revision"])

    assert [
             %{"omitted" => true, "error" => %{"code" => "selection_too_large"}},
             %{"functions" => _}
           ] = oversized.structuredContent["selected"]

    aggregate_doc = String.duplicate("y", 31_900)

    aggregate =
      call(root, 6, "ravens_change", %{
        "base_revision" => oversized.structuredContent["revision"],
        "mode" => "apply_if_valid",
        "operations" => [
          %{
            "op" => "create",
            "kind" => "source_bundle",
            "text" => """
            defmodule McpShop.Large do
              @doc "#{aggregate_doc}"
              def first, do: :first
              @doc "#{aggregate_doc}"
              def second, do: :second
            end
            """
          }
        ],
        "return" => [
          %{"focus" => "function:McpShop.Large.first/0", "include" => ["source"]},
          %{"focus" => "function:McpShop.Large.second/0", "include" => ["source"]}
        ]
      })

    refute aggregate.isError
    assert aggregate.structuredContent["status"] == "applied"
    assert aggregate.structuredContent["working_tree_changed"]
    assert is_binary(aggregate.structuredContent["revision"])

    assert [%{"omitted" => true, "error" => %{"code" => "mcp_output_too_large"}}] =
             aggregate.structuredContent["selected"]
  end

  test "malformed large MCP request retries from retained source", %{root: root} do
    large_doc = String.duplicate("retained request source ", 400)

    source = """
    defmodule McpShop.Retained do
      @moduledoc #{inspect(large_doc, limit: :infinity, printable_limit: :infinity)}
      @doc "Returns a retained value."
      def value, do: :retained
    end
    """

    failed =
      call(root, 40, "ravens_change", %{
        "mode" => "apply_if_valid",
        "unexpected" => true,
        "operations" => [
          %{"op" => "create", "kind" => "source_bundle", "text" => source}
        ]
      })

    assert failed.isError
    assert failed.structuredContent["code"] == "unknown_request_fields"
    assert is_binary(failed.structuredContent["attempt"])
    assert failed.structuredContent["attempt_version"] == 1
    refute File.exists?(Path.join(root, "lib/mcp_shop/retained.ex"))

    repaired =
      call(root, 41, "ravens_retry", %{
        "attempt" => failed.structuredContent["attempt"],
        "attempt_version" => failed.structuredContent["attempt_version"],
        "patch" => [%{"op" => "remove", "path" => "/unexpected"}]
      })

    refute repaired.isError
    assert repaired.structuredContent["status"] == "applied", inspect(repaired.structuredContent)
    assert repaired.structuredContent["verification_complete"]
    assert File.read!(Path.join(root, "lib/mcp_shop/retained.ex")) =~ "def value"
  end

  defp call(root, id, name, arguments) do
    response =
      Server.handle(root, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => "tools/call",
        "params" => %{"name" => name, "arguments" => arguments}
      })

    response["result"]
  end

  defp assert_stdio_round_trip(root) do
    executable = System.find_executable("elixir")

    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, ["-S", "mix", "ravens.mcp", "--root", root]},
        {:cd, File.cwd!()}
      ])

    messages = [
      "{broken",
      Jason.encode!(%{jsonrpc: "2.0", id: 8, method: "ping", params: %{}}),
      Jason.encode!(%{jsonrpc: "2.0", id: 9, method: "tools/list", params: %{"_meta" => %{}}}),
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: 10,
        method: "tools/call",
        params: %{
          "_meta" => %{},
          "name" => "ravens_context",
          "arguments" => %{
            "select" => [%{"focus" => "module:McpShop.Pricing", "include" => ["functions"]}]
          }
        }
      })
    ]

    true = Port.command(port, Enum.join(messages, "\n") <> "\n")
    lines = receive_lines(port, "", 4)
    Port.close(port)

    decoded =
      Enum.map(lines, fn line ->
        assert {:ok, value} = Jason.decode(line)
        value
      end)

    assert Enum.map(decoded, & &1["id"]) == [nil, 8, 9, 10]
    assert Enum.all?(decoded, &(&1["jsonrpc"] == "2.0"))
  end

  defp receive_lines(port, buffer, count) do
    lines = String.split(buffer, "\n", trim: true)

    if length(lines) >= count do
      Enum.take(lines, count)
    else
      receive do
        {^port, {:data, data}} -> receive_lines(port, buffer <> data, count)
      after
        10_000 -> flunk("timed out waiting for MCP STDIO responses: #{inspect(buffer)}")
      end
    end
  end
end
