defmodule TwoRavens.CLIGreenfieldMVPTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Graph
  alias TwoRavens.Repository
  alias TwoRavens.Source

  @moduletag timeout: 240_000

  @discount """
  def discount(subtotal, :vip) when subtotal >= 5_000,
    do: div(subtotal * 10, 100)

  def discount(subtotal, :vip) when subtotal >= 0,
    do: div(subtotal * 5, 100)

  def discount(subtotal, :standard) when subtotal >= 0,
    do: 0
  """

  @test_body """
  use ExUnit.Case, async: true

  test "prices a VIP checkout" do
    assert RavensShop.Checkout.checkout(6_000, :vip) == 5_400
  end
  """

  setup do
    root =
      Path.join(System.tmp_dir!(), "ravens-cli-shop-#{System.unique_integer([:positive])}")

    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(
               mix,
               ["new", root, "--app", "ravens_shop", "--module", "RavensShop"],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root, mix: mix}
  end

  test "the documented CLI flow works across independent processes", %{root: root, mix: mix} do
    assert {init_output, 0} = run_cli(mix, ["ravens", "init", "--root", root])
    assert init_output =~ "schema_version: 1"

    assert {pricing_output, 0} =
             run_cli(mix, [
               "ravens",
               "create",
               "module",
               "RavensShop.Pricing",
               "--root",
               root,
               "--apply"
             ])

    assert pricing_output =~ "candidate applied"
    assert pricing_output =~ "qualification apply isolated=true"

    assert {_output, 0} =
             run_cli(
               mix,
               [
                 "ravens",
                 "create",
                 "function",
                 "RavensShop.Pricing",
                 "--root",
                 root,
                 "--stdin",
                 "--apply"
               ],
               @discount
             )

    assert {_output, 0} =
             run_cli(
               mix,
               [
                 "ravens",
                 "create",
                 "function",
                 "RavensShop.Pricing",
                 "--root",
                 root,
                 "--stdin",
                 "--apply"
               ],
               "def total(subtotal, tier), do: subtotal - discount(subtotal, tier)"
             )

    assert {_output, 0} =
             run_cli(mix, [
               "ravens",
               "create",
               "module",
               "RavensShop.Checkout",
               "--root",
               root,
               "--apply"
             ])

    assert {_output, 0} =
             run_cli(
               mix,
               [
                 "ravens",
                 "create",
                 "function",
                 "RavensShop.Checkout",
                 "--root",
                 root,
                 "--stdin",
                 "--apply"
               ],
               "def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)"
             )

    assert {_output, 0} =
             run_cli(
               mix,
               [
                 "ravens",
                 "create",
                 "module",
                 "RavensShop.PricingTest",
                 "--root",
                 root,
                 "--test",
                 "--stdin",
                 "--apply"
               ],
               @test_body
             )

    focus = "function:RavensShop.Pricing.discount/2"

    assert {context_output, 0} =
             run_cli(mix, ["ravens", "context", focus, "--root", root, "--for-edit"])

    assert context_output =~ "caller function:RavensShop.Pricing.total/2"
    assert context_output =~ "related test RavensShop.PricingTest"
    assert [_, handle] = Regex.run(~r/editable (rv1_[A-Za-z0-9_-]+)\.operator/, context_output)

    pricing_path = Path.join(root, "lib/ravens_shop/pricing.ex")
    before_dry_run = File.read!(pricing_path)

    assert {dry_output, 0} =
             run_cli(mix, ["ravens", "set", handle <> ".operator", ">", "--root", root])

    assert dry_output =~ "candidate dry-run"
    assert dry_output =~ "compile pass"
    assert dry_output =~ "tests pass"
    assert dry_output =~ "qualification qualified_dry_run isolated=true"
    assert dry_output =~ "fallback confirmed"
    assert dry_output =~ "boundary test evidence absent reason=boundary_value_not_exercised"
    assert dry_output =~ "working_tree unchanged"
    assert File.read!(pricing_path) == before_dry_run

    assert {apply_output, 0} =
             run_cli(mix, [
               "ravens",
               "set",
               handle <> ".operator",
               ">",
               "--root",
               root,
               "--apply"
             ])

    assert apply_output =~ "candidate applied"
    assert apply_output =~ "compile pass"
    assert apply_output =~ "tests pass"
    assert File.read!(pricing_path) =~ "subtotal > 5_000"

    assert {:ok, graph} = Source.rebuild(root)
    expected_digest = semantic_digest(graph)
    assert {fresh_digest, 0} = fresh_graph_digest(root)
    assert String.trim(fresh_digest) == expected_digest
  end

  defp run_cli(mix, arguments, input \\ nil)

  defp run_cli(mix, arguments, nil) do
    if :os.type() == {:win32, :nt},
      do: run_windows_batch(mix, arguments, nil),
      else: System.cmd(mix, arguments, cli_options())
  end

  defp run_cli(mix, arguments, input) do
    stdin_path =
      Path.join(
        System.tmp_dir!(),
        "ravens-stdin-#{System.unique_integer([:positive, :monotonic])}.ex"
      )

    try do
      :ok = File.write(stdin_path, input)
      run_with_redirected_stdin(mix, arguments, stdin_path)
    after
      File.rm(stdin_path)
    end
  end

  defp run_with_redirected_stdin(mix, arguments, stdin_path) do
    if :os.type() == {:win32, :nt} do
      run_windows_batch(mix, arguments, stdin_path)
    else
      inner = Enum.map_join([mix | arguments], " ", &shell_quote/1)
      command = "#{inner} < #{shell_quote(stdin_path)}"
      System.cmd("/bin/sh", ["-c", command], cli_options())
    end
  end

  defp run_windows_batch(mix, arguments, stdin_path) do
    script_path =
      Path.join(
        System.tmp_dir!(),
        "ravens-command-#{System.unique_integer([:positive, :monotonic])}.cmd"
      )

    inner = Enum.map_join([mix | arguments], " ", &windows_quote/1)
    redirect = if stdin_path, do: " < #{windows_quote(stdin_path)}", else: ""

    try do
      :ok =
        File.write(
          script_path,
          "@echo off\r\ncall #{inner}#{redirect}\r\nexit /b %ERRORLEVEL%\r\n"
        )

      System.cmd("cmd.exe", ["/d", "/c", script_path], cli_options())
    after
      File.rm(script_path)
    end
  end

  defp fresh_graph_digest(root) do
    mix = System.find_executable("mix") || "mix"

    script_path =
      Path.join(
        System.tmp_dir!(),
        "ravens-fresh-graph-#{System.unique_integer([:positive, :monotonic])}.exs"
      )

    expression = """
    root = System.fetch_env!("RAVENS_FRESH_GRAPH_ROOT")
    {:ok, graph} = TwoRavens.Source.rebuild(root)
    signature = TwoRavens.Graph.semantic_signature(graph)
    IO.puts(TwoRavens.Repository.hash(:erlang.term_to_binary(signature)))
    """

    try do
      :ok = File.write(script_path, expression)

      System.cmd(mix, ["run", "--no-compile", script_path],
        cd: File.cwd!(),
        env: [{"RAVENS_FRESH_GRAPH_ROOT", root}],
        stderr_to_stdout: true
      )
    after
      File.rm(script_path)
    end
  end

  defp semantic_digest(graph) do
    graph |> Graph.semantic_signature() |> :erlang.term_to_binary() |> Repository.hash()
  end

  defp cli_options, do: [cd: File.cwd!(), stderr_to_stdout: true]
  defp windows_quote(value), do: ~s("#{String.replace(value, "\"", "\"\"")}")
  defp shell_quote(value), do: "'#{String.replace(value, "'", "'\\''")}'"
end
