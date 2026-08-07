defmodule TwoRavens.SourceGraphTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Graph
  alias TwoRavens.Repository
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
