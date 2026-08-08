defmodule TwoRavens.SourceGraphTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Graph
  alias TwoRavens.Repository
  alias TwoRavens.Selection
  alias TwoRavens.Selector
  alias TwoRavens.Source

  @pricing """
  defmodule Shop.Pricing do
    @moduledoc "Pricing."
    def discount(subtotal, :vip) when subtotal >= 5_000, do: 500
    def discount(subtotal, :standard) when subtotal >= 0, do: 0
    def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
  end
  """

  @checkout """
  defmodule Shop.Checkout do
    @moduledoc "Checkout."
    def checkout(subtotal, tier), do: Shop.Pricing.total(subtotal, tier)
  end
  """

  @tests """
  defmodule Shop.PricingTest do
    @moduledoc "Tests."
    use ExUnit.Case, async: true
    test "prices checkout" do
      assert Shop.Checkout.checkout(6_000, :vip) == 5_500
    end
  end
  """

  test "derives clauses, guards, calls, transitive callers, and tests deterministically" do
    sources = [
      {"lib/shop/pricing.ex", @pricing},
      {"lib/shop/checkout.ex", @checkout},
      {"test/shop/pricing_test.exs", @tests}
    ]

    fragments = Enum.map(sources, fn {path, source} -> elem(Source.parse(path, source), 1) end)
    hashes = Map.new(sources, fn {path, source} -> {path, Repository.hash(source)} end)
    assert {:ok, graph} = Graph.build(fragments, Repository.revision("missing", hashes))
    discount = "function:Shop.Pricing.discount/2"

    assert {:ok, function} = Graph.function(graph, discount)
    assert length(function.clauses) == 2
    assert hd(function.clauses).guard == "subtotal >= 5000"

    assert [%{operator: ">=", left: "subtotal", right: "5_000"}] =
             hd(function.clauses).comparisons

    assert Graph.callers(graph, discount) == ["function:Shop.Pricing.total/2"]

    assert Graph.upstream(graph, discount) == [
             "function:Shop.Pricing.total/2",
             "function:Shop.Checkout.checkout/2"
           ]

    assert Graph.related_tests(graph, discount) == ["Shop.PricingTest"]
    assert Graph.build(fragments, graph.revision) == {:ok, graph}
  end

  test "unsupported top-level source is disclosed" do
    source = "defmodule Shop.Unsupported do\n  @value 1\nend\n"

    assert {:ok, fragment} = Source.parse("lib/shop/unsupported.ex", source)
    assert fragment.unsupported == ["unsupported top-level form: @"]
  end

  test "aliases and imports resolve managed calls while unsupported bodies stay explicit" do
    alias_source = """
    defmodule Shop.AliasCheckout do
      @moduledoc "Alias checkout."
      alias Shop.Pricing
      def checkout(subtotal, tier), do: Pricing.total(subtotal, tier)
    end
    """

    import_source = """
    defmodule Shop.ImportCheckout do
      @moduledoc "Import checkout."
      import Shop.Pricing
      def checkout(subtotal, tier), do: total(subtotal, tier)
    end
    """

    unsupported_source = """
    defmodule Shop.Branching do
      @moduledoc "Outside the MVP subset."
      def run(value), do: if(value, do: :yes, else: :no)
    end
    """

    {:ok, pricing} = Source.parse("lib/shop/pricing.ex", @pricing)
    {:ok, alias_checkout} = Source.parse("lib/shop/alias_checkout.ex", alias_source)
    {:ok, import_checkout} = Source.parse("lib/shop/import_checkout.ex", import_source)
    {:ok, unsupported} = Source.parse("lib/shop/branching.ex", unsupported_source)
    revision = Repository.revision("missing", %{})
    assert {:ok, graph} = Graph.build([pricing, alias_checkout, import_checkout], revision)

    assert Graph.callees(graph, "function:Shop.AliasCheckout.checkout/2") == [
             "function:Shop.Pricing.total/2"
           ]

    assert Graph.callees(graph, "function:Shop.ImportCheckout.checkout/2") == [
             "function:Shop.Pricing.total/2"
           ]

    assert unsupported.unsupported == ["unsupported function body expression"]
  end

  test "grouped and renamed static aliases resolve managed calls" do
    source = """
    defmodule Shop.AliasedCheckout do
      alias Shop.{Checkout, Pricing}
      alias Shop.Pricing, as: Prices

      def checkout(subtotal, tier), do: Checkout.checkout(subtotal, tier)
      def total(subtotal, tier), do: Pricing.total(subtotal, tier)
      def renamed(subtotal, tier), do: Prices.total(subtotal, tier)
    end
    """

    {:ok, pricing} = Source.parse("lib/shop/pricing.ex", @pricing)
    {:ok, checkout} = Source.parse("lib/shop/checkout.ex", @checkout)
    assert {:ok, aliased} = Source.parse("lib/shop/aliased_checkout.ex", source)
    assert aliased.unsupported == []

    assert {:ok, graph} =
             Graph.build([pricing, checkout, aliased], Repository.revision("missing", %{}))

    assert graph.unsupported == []

    assert Graph.callees(graph, "function:Shop.AliasedCheckout.checkout/2") == [
             "function:Shop.Checkout.checkout/2"
           ]

    for name <- ["renamed", "total"] do
      assert Graph.callees(graph, "function:Shop.AliasedCheckout.#{name}/2") == [
               "function:Shop.Pricing.total/2"
             ]
    end

    call_edges = Enum.filter(graph.edges, &(&1.kind == :calls))

    assert length(call_edges) == 5
    assert length(Enum.uniq_by(call_edges, &{&1.kind, &1.from, &1.to, &1.source})) == 5
  end

  test "dynamic aliases remain explicit unknown" do
    for {name, alias_expression} <- [
          {"DynamicAlias", "Module.concat(Shop, Pricing)"},
          {"ModuleRelativeAlias", "__MODULE__.Pricing"}
        ] do
      source = """
      defmodule Shop.#{name} do
        alias #{alias_expression}
        def total(subtotal, tier), do: Pricing.total(subtotal, tier)
      end
      """

      assert {:ok, fragment} = Source.parse("lib/shop/#{Macro.underscore(name)}.ex", source)
      assert "unsupported top-level alias" in fragment.unsupported

      assert {:ok, graph} =
               Graph.build([fragment], Repository.revision("missing", %{}))

      assert Enum.any?(
               graph.unsupported,
               &String.contains?(&1, "unresolved call Pricing.total/2")
             )
    end
  end

  test "module test selection returns bounded identities, names, and derived targets" do
    sources = [
      {"lib/shop/pricing.ex", @pricing},
      {"lib/shop/checkout.ex", @checkout},
      {"test/shop/pricing_test.exs", @tests}
    ]

    fragments = Enum.map(sources, fn {path, source} -> elem(Source.parse(path, source), 1) end)
    files = Map.new(sources)
    assert {:ok, graph} = Graph.build(fragments, Repository.revision("missing", %{}))

    assert {:ok, selectors} =
             Selector.validate([
               %{"focus" => "module:Shop.PricingTest", "include" => ["tests"]}
             ])

    assert {:ok,
            [
              %{
                focus: "module:Shop.PricingTest",
                tests: [
                  %{
                    focus: "test:Shop.PricingTest:" <> _fingerprint,
                    name: "prices checkout",
                    targets: targets,
                    total_targets: 3,
                    targets_truncated: false
                  }
                ],
                total_tests: 1,
                truncated: false
              }
            ]} = Selection.resolve(graph, files, selectors)

    assert targets == [
             "function:Shop.Checkout.checkout/2",
             "function:Shop.Pricing.discount/2",
             "function:Shop.Pricing.total/2"
           ]
  end

  test "local bindings preserve readable bodies and derived calls" do
    tax_source = """
    defmodule Shop.Tax do
      def tax_cents(subtotal, _region), do: div(subtotal * 25, 100)
    end
    """

    source = """
    defmodule Shop.Totals do
      def calculate(subtotal, region) do
        tax = Shop.Tax.tax_cents(subtotal, region)
        gross = subtotal + tax
        {subtotal, tax, gross}
      end
    end
    """

    assert {:ok, fragment} = Source.parse("lib/shop/totals.ex", source)
    assert fragment.unsupported == []
    assert {:ok, tax} = Source.parse("lib/shop/tax.ex", tax_source)
    assert {:ok, graph} = Graph.build([tax, fragment], Repository.revision("missing", %{}))

    assert Graph.callees(graph, "function:Shop.Totals.calculate/2") == [
             "function:Shop.Tax.tax_cents/2"
           ]
  end

  test "unresolved calls are explicit graph uncertainty" do
    source = """
    defmodule Shop.Unknown do
      @moduledoc "Unknown call."
      def run(value), do: missing(value)
    end
    """

    {:ok, fragment} = Source.parse("lib/shop/unknown.ex", source)
    assert {:ok, graph} = Graph.build([fragment], Repository.revision("missing", %{}))

    assert graph.unsupported == [
             "lib/shop/unknown.ex: unresolved call Shop.Unknown.missing/1 at 3:23"
           ]
  end

  test "duplicate semantic identities fail instead of overwriting source" do
    duplicate = String.replace(@pricing, "500", "600", global: false)
    {:ok, first} = Source.parse("lib/shop/pricing.ex", @pricing)
    {:ok, second} = Source.parse("lib/other/pricing.ex", duplicate)

    assert {:error,
            %{
              code: :ambiguous_identity,
              id: "module:Shop.Pricing",
              sources: sources
            }} = Graph.build([first, second], Repository.revision("missing", %{}))

    assert Enum.map(sources, & &1.path) == ["lib/other/pricing.ex", "lib/shop/pricing.ex"]
  end
end
