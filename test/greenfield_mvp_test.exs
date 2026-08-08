defmodule TwoRavens.GreenfieldMVPTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring
  alias TwoRavens.Context
  alias TwoRavens.Graph
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
    root = Path.join(System.tmp_dir!(), "ravens_shop_#{System.unique_integer([:positive])}")
    executable = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(
               executable,
               ["new", root, "--app", "ravens_shop", "--module", "RavensShop"],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root, mix: executable}
  end

  test "the complete managed CLI/API vertical slice is reconstructable and stale-safe", %{
    root: root,
    mix: mix
  } do
    existing_path = Path.join(root, "lib/ravens_shop.ex")
    existing_source = File.read!(existing_path)

    assert {:ok, _manifest} = Authoring.init(root)
    manifest_before = File.read!(Path.join(root, ".ravens/manifest"))

    assert {:ok, dry_module} = Authoring.create_module(root, "RavensShop.Pricing")
    refute dry_module.applied
    refute File.exists?(Path.join(root, "lib/ravens_shop/pricing.ex"))
    assert File.read!(Path.join(root, ".ravens/manifest")) == manifest_before

    assert {:ok, pricing_module} =
             Authoring.create_module(root, "RavensShop.Pricing", apply: true)

    assert pricing_module.applied

    pricing_path = Path.join(root, "lib/ravens_shop/pricing.ex")
    before_unsupported = File.read!(pricing_path)

    assert {:error, %{code: :unsupported_source}} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def mystery(value), do: unresolved(value)",
               apply: true
             )

    assert File.read!(pricing_path) == before_unsupported

    assert {:ok, discount} =
             Authoring.create_function(root, "RavensShop.Pricing", @discount, apply: true)

    assert discount.details.function == "function:RavensShop.Pricing.discount/2"

    assert {:ok, _total} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def total(subtotal, tier), do: subtotal - discount(subtotal, tier)",
               apply: true
             )

    assert {:ok, _checkout_module} =
             Authoring.create_module(root, "RavensShop.Checkout", apply: true)

    assert {:ok, _checkout} =
             Authoring.create_function(
               root,
               "RavensShop.Checkout",
               "def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)",
               apply: true
             )

    assert {:ok, _test_module} =
             Authoring.create_module(root, "RavensShop.PricingTest",
               test: true,
               source: @test_body,
               apply: true
             )

    focus = "function:RavensShop.Pricing.discount/2"
    assert {:ok, context} = Context.query(root, focus, for_edit: true)
    assert context.callers == ["function:RavensShop.Pricing.total/2"]

    assert context.upstream == [
             "function:RavensShop.Pricing.total/2",
             "function:RavensShop.Checkout.checkout/2"
           ]

    assert context.tests == ["RavensShop.PricingTest"]
    first_edit = hd(context.editable_comparisons)
    handle = first_edit.handle <> ".operator"
    before_dry_run = File.read!(pricing_path)

    assert {:ok, dry_set} = Authoring.set(root, handle, ">")
    refute dry_set.applied
    assert dry_set.details.changed_lines == 1

    assert dry_set.details.boundary.test_evidence == %{
             status: :absent,
             reason: :boundary_value_not_exercised
           }

    assert dry_set.details.boundary.fallback.status == :confirmed

    assert File.read!(pricing_path) == before_dry_run

    manifest_before_failure = File.read!(Path.join(root, ".ravens/manifest"))

    assert {:error, %{code: :qualification_failed}} =
             Authoring.create_module(root, "RavensShop.FailingTest",
               test: true,
               source: "use ExUnit.Case\ntest \"fails\", do: assert(false)",
               apply: true
             )

    refute File.exists?(Path.join(root, "test/ravens_shop/failing_test.exs"))
    assert File.read!(Path.join(root, ".ravens/manifest")) == manifest_before_failure
    assert File.read!(pricing_path) == before_dry_run

    assert {:ok, applied_set} = Authoring.set(root, handle, ">", apply: true)
    assert applied_set.applied
    assert applied_set.evidence.accepted_graph == :pass
    assert File.read!(pricing_path) =~ "subtotal > 5_000"
    refute File.read!(pricing_path) =~ "subtotal >= 5_000"

    assert {:error, %{code: :stale_handle}} = Authoring.set(root, handle, ">")
    assert File.read!(existing_path) == existing_source

    assert {:ok, rebuilt} = Source.rebuild(root)
    assert Graph.semantic_signature(rebuilt) == Graph.semantic_signature(applied_set.graph)
    assert rebuilt == Source.rebuild(root) |> elem(1)

    {cli_output, 0} =
      System.cmd(mix, ["ravens", "context", focus, "--root", root, "--for-edit"],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert cli_output =~ "revision #{String.slice(rebuilt.revision.working_hash, 0, 12)}"
    assert cli_output =~ "test source_derived RavensShop.PricingTest statically_related"
    assert cli_output =~ "frontier unmanaged repository source is outside the MVP index"
  end
end
