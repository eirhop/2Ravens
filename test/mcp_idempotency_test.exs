defmodule TwoRavens.MCPIdempotencyTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring

  @moduletag timeout: 300_000

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-mcp-retry-#{System.unique_integer([:positive])}")
    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(mix, ["new", root, "--app", "mcp_retry"], stderr_to_stdout: true)

    assert {:ok, _manifest} = Authoring.init(root)

    assert {:ok, _candidate} =
             Authoring.create_module(root, "McpRetry.Pricing",
               source: "def net(subtotal, discount), do: subtotal - discount",
               apply: true
             )

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "one context and one bundled change replay exactly after an unknown outcome", %{root: root} do
    context =
      process_call(root, 1, "ravens_context", %{
        "select" => [
          %{
            "focus" => "function:McpRetry.Pricing.net/2",
            "include" => ["source", "callers"]
          }
        ]
      })

    refute context["isError"]
    base_revision = context["structuredContent"]["base_revision"]

    request = %{
      "request_id" => "mcp-retry.bundle:v1",
      "base_revision" => base_revision,
      "mode" => "apply_if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => bundle()
        }
      ],
      "return" => [
        %{
          "focus" => "function:McpRetry.Totals.calculate/2",
          "include" => ["source", "callees"]
        },
        %{"focus" => "module:McpRetry.TotalsTest", "include" => ["tests"]}
      ]
    }

    first = process_call(root, 2, "ravens_change", request)
    refute first["isError"]

    receipt = first["structuredContent"]
    assert receipt["status"] == "applied"
    assert receipt["selected_from"] == %{"revision" => receipt["revision"]}

    assert [%{"source" => source, "callees" => callees}, %{"tests" => [test]}] =
             receipt["selected"]

    assert source =~ "def calculate"
    assert "function:McpRetry.Pricing.net/2" in callees
    assert "function:McpRetry.TaxPolicy.tax/1" in callees
    assert test["name"] == "calculates net tax and gross"
    assert "function:McpRetry.Totals.calculate/2" in test["targets"]

    replayed = process_call(root, 3, "ravens_change", request)
    refute replayed["isError"]
    assert replayed["structuredContent"] == receipt

    conflicting = put_in(request, ["operations", Access.at(0), "text"], different_bundle())
    rejected = process_call(root, 4, "ravens_change", conflicting)

    assert rejected["isError"]
    assert rejected["structuredContent"]["code"] == "request_id_conflict"
    refute File.exists?(Path.join(root, "lib/mcp_retry/different.ex"))
  end

  defp bundle do
    """
    defmodule McpRetry.TaxPolicy do
      @moduledoc "Calculates tax."
      def tax(net), do: div(net * 20, 100)
    end

    defmodule McpRetry.Totals do
      @moduledoc "Calculates order totals."
      alias McpRetry.{Pricing, TaxPolicy}

      def calculate(subtotal, discount) do
        net = Pricing.net(subtotal, discount)
        tax = TaxPolicy.tax(net)
        {net, tax, net + tax}
      end
    end

    defmodule McpRetry.TotalsTest do
      use ExUnit.Case, async: true
      alias McpRetry.Totals

      test "calculates net tax and gross" do
        assert Totals.calculate(1_000, 100) == {900, 180, 1_080}
      end
    end
    """
  end

  defp different_bundle do
    """
    defmodule McpRetry.Different do
      def value, do: :different
    end
    """
  end

  defp process_call(root, id, name, arguments) do
    port = start_server(root)

    request =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: id,
        method: "tools/call",
        params: %{name: name, arguments: arguments}
      })

    true = Port.command(port, request <> "\n")
    response = receive_line(port, "")
    Port.close(port)

    assert {:ok, %{"result" => result}} = Jason.decode(response)
    result
  end

  defp start_server(root) do
    executable = System.find_executable("elixir")

    Port.open({:spawn_executable, String.to_charlist(executable)}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, ["-S", "mix", "ravens.mcp", "--root", root]},
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
          180_000 -> flunk("timed out waiting for MCP response")
        end
    end
  end
end
