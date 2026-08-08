defmodule TwoRavens.ChangeTestEntitiesTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring
  alias TwoRavens.Change
  alias TwoRavens.Semantic.Revision
  alias TwoRavens.Source

  @moduletag timeout: 300_000

  setup do
    root =
      Path.join(System.tmp_dir!(), "ravens-test-entity-#{System.unique_integer([:positive])}")

    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(
               mix,
               ["new", root, "--app", "test_entity_shop", "--module", "TestEntityShop"],
               stderr_to_stdout: true
             )

    assert {:ok, _manifest} = Authoring.init(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "a failed assertion is repaired by one exact test patch without resending its module", %{
    root: root
  } do
    assert {:ok, failed} =
             Change.submit(root, %{
               "mode" => "apply_if_valid",
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule TestEntityShop.Promise do
                     @moduledoc "Calculates delivery promises."
                     def days(:standard, 501, :regional), do: 13
                   end

                   defmodule TestEntityShop.PromiseTest do
                     use ExUnit.Case, async: true

                     test "includes the regional backorder delay" do
                       assert TestEntityShop.Promise.days(:standard, 501, :regional) == 11
                     end
                   end
                   """
                 }
               ],
               "return" => [
                 %{"focus" => "module:TestEntityShop.PromiseTest", "include" => ["tests"]}
               ]
             })

    assert failed.status == :needs_changes
    assert failed.qualification == nil
    assert [%{tests: [%{focus: test_id}]}] = failed.selected
    assert String.starts_with?(test_id, "test:TestEntityShop.PromiseTest:")
    refute File.exists?(Path.join(root, "test/test_entity_shop/promise_test.exs"))

    assert {:ok, repaired} =
             Change.submit(root, %{
               "draft" => failed.draft,
               "draft_version" => failed.draft_version,
               "mode" => "apply_if_valid",
               "operations" => [
                 %{
                   "op" => "patch",
                   "target" => test_id,
                   "diff" => """
                   @@
                   -    assert TestEntityShop.Promise.days(:standard, 501, :regional) == 11
                   +    assert TestEntityShop.Promise.days(:standard, 501, :regional) == 13
                   """
                 }
               ],
               "return" => [
                 %{
                   "focus" => test_id,
                   "include" => ["source", "targets", "path", "editable"]
                 }
               ]
             })

    assert repaired.status == :applied
    assert repaired.operation_count == 1
    assert repaired.qualification.tests == :pass
    assert [%{focus: ^test_id} = selected] = repaired.selected
    assert selected.source =~ "== 13"
    assert selected.targets == ["function:TestEntityShop.Promise.days/3"]
    assert selected.path.path == "test/test_entity_shop/promise_test.exs"
    assert selected.editable.operations == ["patch", "replace", "delete"]

    assert {:ok, graph} = Source.rebuild(root)
    assert Map.has_key?(graph.nodes, test_id)
    assert File.read!(Path.join(root, "test/test_entity_shop/promise_test.exs")) =~ "== 13"
  end

  test "exact test replacement preserves identity and exact deletion removes only that test", %{
    root: root
  } do
    assert {:ok, created} = Change.submit(root, passing_bundle_request())
    assert created.status == :applied

    assert {:ok, graph} = Source.rebuild(root)
    test_id = test_id(graph)
    revision = Revision.from_repository(graph.revision, :available).id

    assert {:ok, replaced} =
             Change.submit(root, %{
               "base_revision" => revision,
               "mode" => "apply_if_valid",
               "operations" => [
                 %{
                   "op" => "replace",
                   "target" => test_id,
                   "text" => """
                   test "calculates the promise" do
                     result = TestEntityShop.Replaceable.days()
                     assert result == 13
                   end
                   """
                 }
               ],
               "return" => [
                 %{"focus" => test_id, "include" => ["source", "editable"]}
               ]
             })

    assert replaced.status == :applied
    assert [%{focus: ^test_id, source: source}] = replaced.selected
    assert source =~ "result = TestEntityShop.Replaceable.days()"

    assert {:ok, replaced_graph} = Source.rebuild(root)
    assert Map.has_key?(replaced_graph.nodes, test_id)
    replaced_revision = Revision.from_repository(replaced_graph.revision, :available).id

    assert {:ok, deleted} =
             Change.submit(root, %{
               "base_revision" => replaced_revision,
               "mode" => "apply_if_valid",
               "operations" => [%{"op" => "delete", "target" => test_id}]
             })

    assert deleted.status == :applied
    assert {:ok, final_graph} = Source.rebuild(root)
    refute Map.has_key?(final_graph.nodes, test_id)
    assert Map.has_key?(final_graph.nodes, "module:TestEntityShop.ReplaceableTest")
    assert Map.has_key?(final_graph.nodes, "function:TestEntityShop.Replaceable.days/0")
  end

  test "a newly created module can be deleted and recreated at the same path in one draft", %{
    root: root
  } do
    assert {:ok, receipt} =
             Change.submit(root, %{
               "mode" => "apply_if_valid",
               "operations" => [
                 source_bundle("def value, do: :first"),
                 %{
                   "op" => "delete",
                   "target" => "module:TestEntityShop.Recreated",
                   "cascade" => true
                 },
                 source_bundle("def value, do: :second")
               ]
             })

    assert receipt.status == :applied
    assert receipt.operation_count == 3
    path = Path.join(root, "lib/test_entity_shop/recreated.ex")
    assert File.read!(path) =~ ":second"
    refute File.read!(path) =~ ":first"

    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    assert {:error, collision} =
             Change.submit(root, %{
               "base_revision" => revision,
               "mode" => "draft_only",
               "operations" => [
                 %{
                   "op" => "delete",
                   "target" => "module:TestEntityShop.Recreated",
                   "cascade" => true
                 },
                 source_bundle("def value, do: :replacement")
               ]
             })

    assert collision.code == :module_collision
    assert File.read!(path) =~ ":second"
  end

  defp passing_bundle_request do
    %{
      "mode" => "apply_if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => """
          defmodule TestEntityShop.Replaceable do
            def days, do: 13
          end

          defmodule TestEntityShop.ReplaceableTest do
            use ExUnit.Case, async: true

            test "calculates the promise" do
              assert TestEntityShop.Replaceable.days() == 13
            end
          end
          """
        }
      ]
    }
  end

  defp test_id(graph) do
    graph.nodes
    |> Map.keys()
    |> Enum.find(&String.starts_with?(&1, "test:TestEntityShop.ReplaceableTest:"))
  end

  defp source_bundle(body) do
    %{
      "op" => "create",
      "kind" => "source_bundle",
      "text" => """
      defmodule TestEntityShop.Recreated do
        #{body}
      end
      """
    }
  end
end
