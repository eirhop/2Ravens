defmodule TwoRavens.ChangeCLITest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring

  @moduletag timeout: 300_000

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-change-cli-#{System.unique_integer([:positive])}")
    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(mix, ["new", root, "--app", "cli_shop", "--module", "CliShop"],
               stderr_to_stdout: true
             )

    assert {:ok, _manifest} = Authoring.init(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{mix: mix, root: root}
  end

  test "guide is compact, accurate, and available without a project root", %{mix: mix} do
    assert {guide, 0} = System.cmd(mix, ["ravens", "guide"], stderr_to_stdout: true)
    assert guide =~ ~s("mode":"apply_if_valid")
    assert guide =~ "draft_only: qualify and retain a ready draft"
    assert guide =~ "edit existing code by exact entity only"
    assert guide =~ "no intent or relationship fields"
    assert byte_size(guide) < 1_600

    assert {help, 0} = System.cmd(mix, ["ravens", "change", "--help"], stderr_to_stdout: true)
    assert help == guide
  end

  test "change request file and draft context are callable across CLI processes", %{
    mix: mix,
    root: root
  } do
    request_path = Path.join(System.tmp_dir!(), "ravens-request-#{System.unique_integer()}.json")

    request = %{
      "mode" => "apply_if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => """
          defmodule CliShop.Price do
            @moduledoc "Calculates CLI probe prices."
            def amount, do: missing_value()
          end
          """
        }
      ]
    }

    File.write!(request_path, Jason.encode!(request))
    on_exit(fn -> File.rm(request_path) end)

    assert {output, 0} =
             System.cmd(mix, ["ravens", "change", "--root", root, "--request", request_path],
               stderr_to_stdout: true
             )

    assert output =~ "status needs_changes"
    assert output =~ "working_tree unchanged"
    [_, draft, version] = Regex.run(~r/draft (draft:[^ ]+) version=(\d+)/, output)

    assert {context, 0} =
             System.cmd(
               mix,
               [
                 "ravens",
                 "draft-context",
                 draft,
                 version,
                 "function:CliShop.Price.amount/0",
                 "--root",
                 root
               ],
               stderr_to_stdout: true
             )

    assert context =~ "entity function:CliShop.Price.amount/0"
    assert context =~ "diagnostic"
    refute File.exists?(Path.join(root, "lib/cli_shop/price.ex"))
  end

  test "change JSON must be an object", %{mix: mix, root: root} do
    request_path = Path.join(System.tmp_dir!(), "ravens-request-#{System.unique_integer()}.json")
    File.write!(request_path, "[]")
    on_exit(fn -> File.rm(request_path) end)

    assert {output, status} =
             System.cmd(mix, ["ravens", "change", "--root", root, "--request", request_path],
               stderr_to_stdout: true
             )

    assert status != 0
    assert output =~ "invalid_change_json"
  end

  test "revision and entity discovery return exact identities without source", %{
    mix: mix,
    root: root
  } do
    request_path = Path.join(System.tmp_dir!(), "ravens-request-#{System.unique_integer()}.json")

    request = %{
      "mode" => "apply_if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => "defmodule CliShop.Discovery do\n  def value, do: :ok\nend"
        }
      ]
    }

    File.write!(request_path, Jason.encode!(request))
    on_exit(fn -> File.rm(request_path) end)

    assert {_output, 0} =
             System.cmd(mix, ["ravens", "change", "--root", root, "--request", request_path],
               stderr_to_stdout: true
             )

    assert {revision, 0} =
             System.cmd(mix, ["ravens", "revision", "--root", root], stderr_to_stdout: true)

    assert revision =~ ~r/revision revision:r_[A-Za-z0-9_-]+/

    assert {entities, 0} =
             System.cmd(mix, ["ravens", "entities", "--root", root], stderr_to_stdout: true)

    assert entities =~ "entity module:CliShop.Discovery"
    assert entities =~ "entity function:CliShop.Discovery.value/0"
    refute entities =~ "def value"
  end
end
