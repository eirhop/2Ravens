defmodule TwoRavens.DiscoveryTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Discovery
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore

  @allocation """
  defmodule Atlas.Inventory.Allocation do
    @moduledoc "Allocates warehouse stock to eligible orders."

    @doc "Reserves available warehouse units."
    def reserve(order), do: Atlas.Inventory.Policy.allowed?(order)
  end
  """

  @other_allocation """
  defmodule Atlas.Regional.Allocation do
    @moduledoc "Allocates regional capacity."

    @doc "Reserves regional capacity."
    def reserve(order), do: order
  end
  """

  @policy """
  defmodule Atlas.Inventory.Policy do
    @moduledoc false

    @doc false
    def allowed?(_order), do: true

    defp normalize(order), do: order
  end
  """

  @promise """
  defmodule Atlas.Shipping.Promise do
    @moduledoc "Calculates delivery promise dates for allocated orders."

    @doc "Returns promised delivery days after reserving warehouse stock."
    def days(order), do: Atlas.Inventory.Allocation.reserve(order)
  end
  """

  @tests """
  defmodule Atlas.Shipping.PromiseTest do
    use ExUnit.Case, async: true

    test "returns the delivery promise" do
      assert Atlas.Shipping.Promise.days(:order) == 2
    end
  end
  """

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-discovery-#{System.unique_integer([:positive])}")

    sources = [
      {"lib/atlas/inventory/allocation.ex", @allocation},
      {"lib/atlas/inventory/policy.ex", @policy},
      {"lib/atlas/regional/allocation.ex", @other_allocation},
      {"lib/atlas/shipping/promise.ex", @promise},
      {"test/atlas/shipping/promise_test.exs", @tests}
    ]

    File.mkdir_p!(root)
    File.write!(Path.join(root, "mix.exs"), "defmodule DiscoveryFixture.MixProject do\nend\n")

    Enum.each(sources, fn {path, source} ->
      absolute = Path.join(root, path)
      File.mkdir_p!(Path.dirname(absolute))
      File.write!(absolute, source)
    end)

    assert {:ok, project} = Project.open(root)
    assert {:ok, manifest} = Manifest.init(project)

    manifest =
      Enum.reduce(sources, manifest, fn {path, _source}, manifest ->
        assert {:ok, updated} = Manifest.add(manifest, path)
        updated
      end)

    assert :ok = Manifest.write(project, manifest)
    assert {:ok, _freshness} = SemanticStore.initialize(project, manifest)

    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "exact focus returns one canonical module with path, docs, and public functions", %{
    root: root
  } do
    assert {:ok, result} =
             Discovery.query(root, %{"query" => "module:Atlas.Inventory.Policy"})

    assert result.status == :exact
    assert String.starts_with?(result.base_revision, "revision:r_")

    assert [module] = result.results
    assert module.focus == "module:Atlas.Inventory.Policy"
    assert module.path == "lib/atlas/inventory/policy.ex"
    assert module.start_line == 1
    assert module.doc == nil
    refute module.public_functions_truncated

    assert [function] = module.public_functions
    assert function.focus == "function:Atlas.Inventory.Policy.allowed?/1"
    assert function.signature == "allowed?/1"
    assert function.visibility == :public
    assert function.doc == nil
    refute Enum.any?(module.public_functions, &String.contains?(&1.focus, "normalize"))
  end

  test "exact function suffix includes derived relationship counts", %{root: root} do
    assert {:ok, result} =
             Discovery.query(root, %{"query" => "Promise.days/1", "kinds" => ["function"]})

    assert result.status == :exact

    assert [function] = result.results
    assert function.focus == "function:Atlas.Shipping.Promise.days/1"
    assert function.path == "lib/atlas/shipping/promise.ex"
    assert function.signature == "days/1"
    assert function.visibility == :public
    assert function.caller_count == 0
    assert function.callee_count == 1
    assert function.test_count == 1
  end

  test "name prefixes and documentation tokens find canonical functions", %{root: root} do
    assert {:ok, prefix} =
             Discovery.query(root, %{"query" => "allo", "kinds" => ["module"]})

    assert prefix.status == :matches

    assert Enum.map(prefix.results, & &1.focus) == [
             "module:Atlas.Inventory.Allocation",
             "module:Atlas.Regional.Allocation"
           ]

    assert {:ok, docs} =
             Discovery.query(root, %{
               "query" => "promised delivery",
               "kinds" => ["function"]
             })

    assert docs.status == :matches

    assert [%{focus: "function:Atlas.Shipping.Promise.days/1", match: :documentation}] =
             docs.results
  end

  test "ambiguous suffix and missing identity stay explicit with bounded suggestions", %{
    root: root
  } do
    assert {:ok, ambiguous} =
             Discovery.query(root, %{"query" => "Allocation", "kinds" => ["module"]})

    assert ambiguous.status == :ambiguous

    assert Enum.map(ambiguous.results, & &1.focus) == [
             "module:Atlas.Inventory.Allocation",
             "module:Atlas.Regional.Allocation"
           ]

    assert {:ok, missing} =
             Discovery.query(root, %{
               "query" => "Atlas.Allocation",
               "kinds" => ["module"]
             })

    assert missing.status == :not_found
    assert missing.results == []

    assert Enum.map(missing.suggestions, & &1.focus) == [
             "module:Atlas.Inventory.Allocation",
             "module:Atlas.Regional.Allocation"
           ]
  end

  test "wildcard listing and documentation are bounded and deterministically ordered", %{
    root: root
  } do
    long_doc = String.duplicate("documented ", 40)
    long_path = Path.join(root, "lib/atlas/verbose.ex")

    File.write!(
      long_path,
      "defmodule Atlas.Verbose do\n  @moduledoc #{inspect(long_doc)}\nend\n"
    )

    assert {:ok, project} = Project.open(root)
    assert {:ok, manifest} = Manifest.load(project)
    assert {:ok, manifest} = Manifest.add(manifest, "lib/atlas/verbose.ex")
    assert :ok = Manifest.write(project, manifest)

    assert {:ok, first} = Discovery.query(root, %{"query" => "*", "limit" => 2})
    assert {:ok, second} = Discovery.query(root, %{"query" => "*", "limit" => 2})

    assert first.results == second.results
    assert first.truncated

    assert Enum.map(first.results, & &1.focus) == [
             "module:Atlas.Inventory.Allocation",
             "module:Atlas.Inventory.Policy"
           ]

    assert {:ok, verbose} =
             Discovery.query(root, %{"query" => "module:Atlas.Verbose", "limit" => 1})

    assert [module] = verbose.results
    assert String.length(module.doc) == 240
    assert String.ends_with?(module.doc, "…")
  end

  test "flat request validation enforces query, kind, and result bounds", %{root: root} do
    assert {:error, %{code: :invalid_discovery_query, reason: :required_string}} =
             Discovery.query(root, %{})

    assert {:ok, clamped} = Discovery.query(root, %{"query" => "*", "limit" => 100})

    assert clamped.warnings == [
             %{code: :discovery_limit_clamped, requested: 100, applied: 20}
           ]

    assert {:error, %{code: :invalid_discovery_kinds}} =
             Discovery.query(root, %{"query" => "*", "kinds" => ["test"]})

    assert {:error, %{code: :invalid_discovery_request, fields: ["surprise"]}} =
             Discovery.query(root, %{"query" => "*", "surprise" => true})
  end
end
