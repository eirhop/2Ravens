defmodule TwoRavens.BoundaryTestEvidenceTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Authoring.BoundaryTestEvidence
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Source

  setup do
    root =
      Path.join(System.tmp_dir!(), "two-ravens-boundary-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib/shop"))
    File.mkdir_p!(Path.join(root, "test/shop"))
    File.write!(Path.join(root, "mix.exs"), "defmodule Temporary.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "computed test arguments are not reported as absent boundary evidence", %{root: root} do
    pricing = """
    defmodule Shop.Pricing do
      def eligible(_code, subtotal) when subtotal >= 5_000, do: subtotal
    end
    """

    pricing_test = """
    defmodule Shop.PricingTest do
      use ExUnit.Case

      test "uses a computed boundary" do
        assert Shop.Pricing.eligible(0, 2_500 * 2) == 5_000
      end
    end
    """

    File.write!(Path.join(root, "lib/shop/pricing.ex"), pricing)
    File.write!(Path.join(root, "test/shop/pricing_test.exs"), pricing_test)

    assert {:ok, project} = Project.open(root)
    assert {:ok, manifest} = Manifest.init(project)
    assert {:ok, manifest} = Manifest.add(manifest, "lib/shop/pricing.ex")
    assert {:ok, manifest} = Manifest.add(manifest, "test/shop/pricing_test.exs")
    assert :ok = Manifest.write(project, manifest)
    assert {:ok, graph} = Source.rebuild(project, manifest)

    comparison =
      graph.nodes
      |> Map.values()
      |> Enum.find(&match?(%TwoRavens.Source.Comparison{}, &1))

    assert BoundaryTestEvidence.analyze(
             project,
             graph,
             ["Shop.PricingTest"],
             comparison
           ) == %{status: :present, reason: :boundary_value_derived}

    dynamic_test = """
    defmodule Shop.PricingTest do
      use ExUnit.Case

      test "mixes static and dynamic calls" do
        assert Shop.Pricing.eligible(0, 6_000) == 6_000
        assert apply(Shop.Pricing, :eligible, [0, 5_000]) == 5_000
      end
    end
    """

    File.write!(Path.join(root, "test/shop/pricing_test.exs"), dynamic_test)
    assert {:ok, dynamic_graph} = Source.rebuild(project, manifest)

    assert BoundaryTestEvidence.analyze(
             project,
             dynamic_graph,
             ["Shop.PricingTest"],
             comparison
           ) == %{status: :unknown, reason: :test_argument_flow_not_derived}

    short_circuit_test = """
    defmodule Shop.PricingTest do
      use ExUnit.Case

      def always_true, do: true

      test "does not execute the right branch" do
        assert always_true() or Shop.Pricing.eligible(0, 5_000)
      end
    end
    """

    File.write!(Path.join(root, "test/shop/pricing_test.exs"), short_circuit_test)
    assert {:ok, short_circuit_graph} = Source.rebuild(project, manifest)

    assert BoundaryTestEvidence.analyze(
             project,
             short_circuit_graph,
             ["Shop.PricingTest"],
             comparison
           ) == %{status: :unknown, reason: :test_argument_flow_not_derived}
  end
end
