defmodule TwoRavens.TestEntitySelectionTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Graph
  alias TwoRavens.Repository
  alias TwoRavens.Selection
  alias TwoRavens.Selector
  alias TwoRavens.Source

  test "an exact test focus returns source, targets, path, and edit evidence" do
    production = """
    defmodule SelectionShop.Promise do
      def days, do: 13
    end
    """

    tests = """
    defmodule SelectionShop.PromiseTest do
      use ExUnit.Case, async: true

      test "calculates the promise" do
        assert SelectionShop.Promise.days() == 13
      end
    end
    """

    sources = [
      {"lib/selection_shop/promise.ex", production},
      {"test/selection_shop/promise_test.exs", tests}
    ]

    fragments = Enum.map(sources, fn {path, source} -> elem(Source.parse(path, source), 1) end)
    files = Map.new(sources)
    assert {:ok, graph} = Graph.build(fragments, Repository.revision("missing", %{}))

    test_id =
      graph.nodes
      |> Map.keys()
      |> Enum.find(&String.starts_with?(&1, "test:SelectionShop.PromiseTest:"))

    assert {:ok, selectors} =
             Selector.validate([
               %{
                 "focus" => test_id,
                 "include" => ["source", "targets", "path", "editable", "evidence"]
               }
             ])

    assert {:ok, [selected]} = Selection.resolve(graph, files, selectors)
    assert selected.focus == test_id
    assert selected.source =~ "assert SelectionShop.Promise.days() == 13"
    assert selected.content_bytes == byte_size(selected.source)
    assert selected.targets == ["function:SelectionShop.Promise.days/0"]

    assert selected.path == %{
             path: "test/selection_shop/promise_test.exs",
             start_line: 4,
             end_line: 6
           }

    assert selected.editable.operations == ["patch", "replace", "delete"]
    assert is_binary(selected.editable.hash)
    assert selected.evidence.origin == :source_parser
  end
end
