defmodule TwoRavens.SemanticMemoryMVPTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias TwoRavens.Authoring
  alias TwoRavens.Context
  alias TwoRavens.Manifest
  alias TwoRavens.Materializer
  alias TwoRavens.Project
  alias TwoRavens.Qualification.Evidence, as: QualificationEvidence
  alias TwoRavens.Semantic.Origin
  alias TwoRavens.SemanticStore

  @moduletag timeout: 300_000

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
    root = Path.join(System.tmp_dir!(), "ravens-memory-#{System.unique_integer([:positive])}")
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

  test "accepted memory survives processes, source movement, rename, and database loss", %{
    root: root,
    mix: mix
  } do
    assert {:ok, _manifest} = Authoring.init(root)
    assert File.regular?(Path.join(root, ".ravens/semantic.sqlite3"))

    assert File.read!(Path.join(root, ".ravens/.gitignore")) ==
             "semantic.sqlite3\nsemantic.sqlite3-*\n"

    assert {:ok, _module} =
             Authoring.create_module(root, "RavensShop.Pricing", apply: true)

    assert {:ok, dry_intent} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def preview(subtotal), do: subtotal",
               intent: "This dry-run intent must not persist"
             )

    refute dry_intent.applied

    assert {:error, %{code: :function_not_found}} =
             Context.query(root, "function:RavensShop.Pricing.preview/1", include: ["intent"])

    assert {:ok, _discount} =
             Authoring.create_function(root, "RavensShop.Pricing", @discount, apply: true)

    assert {:ok, total} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def total(subtotal, tier), do: subtotal - discount(subtotal, tier)",
               intent: "Calculate final price after the tier discount",
               apply: true
             )

    assert total.semantic.receipt.requested_intents == 1
    assert total.semantic.receipt.entity_id =~ "entity:n_"

    compact_receipt = TwoRavens.CLI.candidate(total)
    detailed_receipt = TwoRavens.CLI.candidate(total, details: true)
    refute compact_receipt =~ "@@"
    assert detailed_receipt =~ "source diff"
    assert byte_size(compact_receipt) < byte_size(detailed_receipt)

    assert {:ok, _module} =
             Authoring.create_module(root, "RavensShop.Checkout", apply: true)

    assert {:ok, _checkout} =
             Authoring.create_function(
               root,
               "RavensShop.Checkout",
               "def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)",
               apply: true
             )

    focus = "function:RavensShop.Pricing.total/2"

    assert {:ok, test_candidate} =
             Authoring.create_module(root, "RavensShop.PricingTest",
               test: true,
               source: @test_body,
               for: [focus],
               intent: "Protect VIP checkout pricing",
               apply: true
             )

    assert test_candidate.semantic.receipt.requested_intents == 1

    assert {:ok, context} =
             Context.query(root, focus, include: ["intent", "callers", "tests", "evidence"])

    stable_entity = context.entity.id
    assert context.freshness.graph_rebuilt == false

    assert Enum.map(context.intents, & &1.text) == [
             "Calculate final price after the tier discount"
           ]

    assert context.callers == ["function:RavensShop.Checkout.checkout/2"]
    assert context.tests == ["RavensShop.PricingTest"]

    assert Enum.map(context.requested_tests, & &1.semantic_key) ==
             ["module:RavensShop.PricingTest"]

    assert Enum.any?(context.evidence, fn evidence ->
             evidence.type == "function_coverage" and evidence.status == "unknown" and
               evidence.origin == "test_observed" and
               evidence.reason == "coverage_not_captured"
           end)

    assert {fresh_output, 0} =
             run_cli(mix, [
               "ravens",
               "context",
               focus,
               "--root",
               root,
               "--include",
               "intent,callers,tests,evidence",
               "--compact"
             ])

    assert fresh_output =~ "focus #{stable_entity} #{focus}"
    assert fresh_output =~ ~s(intent requested "Calculate final price after the tier discount")
    assert fresh_output =~ "caller source_derived function:RavensShop.Checkout.checkout/2"
    assert fresh_output =~ "test requested RavensShop.PricingTest intended_to_test"
    assert fresh_output =~ "function_coverage unknown reason=coverage_not_captured"
    refute fresh_output =~ "def total"

    compact_output = String.trim_trailing(fresh_output)
    assert [_, reported_bytes] = Regex.run(~r/output_bytes (\d+)\z/, compact_output)
    assert String.to_integer(reported_bytes) == byte_size(compact_output)
    assert byte_size(compact_output) < 1_000

    assert {:ok, detailed_context} = Context.query(root, focus, details: true)
    detailed_output = TwoRavens.CLI.context(detailed_context, details: true)
    assert detailed_output =~ "def total(subtotal, tier)"
    assert detailed_output =~ "details provenance"
    assert byte_size(detailed_output) > byte_size(compact_output)

    moved_focus = move_and_rename_total(root)

    assert {:ok, moved} =
             Context.query(root, moved_focus, include: ["intent", "callers", "tests", "evidence"])

    assert moved.freshness.graph_rebuilt
    assert moved.entity.id == stable_entity
    assert Enum.map(moved.intents, & &1.text) == ["Calculate final price after the tier discount"]
    assert moved.callers == ["function:RavensShop.Checkout.checkout/2"]
    assert Enum.map(moved.requested_tests, & &1.semantic_key) == ["module:RavensShop.PricingTest"]

    File.rm!(Path.join(root, ".ravens/semantic.sqlite3"))

    assert {:ok, reconstructed} =
             Context.query(root, moved_focus, include: ["intent", "callers", "tests", "evidence"])

    assert reconstructed.freshness.status == :reconstructed
    assert reconstructed.entity.id =~ "entity:reconstructed_"
    assert reconstructed.entity.id != stable_entity
    assert reconstructed.intents == []
    assert reconstructed.requested_tests == []
    assert hd(reconstructed.caller_relations).origin == "reconstructed"
    assert reconstructed.freshness.intent_status == "unavailable"
    assert reconstructed.freshness.intent_reason == :semantic_store_rebuilt_from_source

    output = TwoRavens.CLI.context(reconstructed)
    assert output =~ "intent unavailable reason=semantic_store_rebuilt_from_source"
    refute output =~ "Calculate final price after the tier discount"

    moved_path = Path.join(root, "lib/ravens_shop/catalog/pricing.ex")

    unsupported_source =
      File.read!(moved_path)
      |> String.replace("\nend\n", "\n  def mystery(value), do: unresolved(value)\nend\n")

    File.write!(moved_path, unsupported_source)

    assert {:ok, unresolved} = Context.query(root, moved_focus, include: ["evidence"])
    assert unresolved.freshness.status == :unresolved
    assert Enum.any?(unresolved.frontier, &String.contains?(&1, "unresolved"))

    duplicate_relative = "lib/ravens_shop/catalog/pricing_copy.ex"
    File.write!(Path.join(root, duplicate_relative), unsupported_source)
    assert {:ok, project} = Project.open(root)
    assert {:ok, manifest} = Manifest.load(project)
    assert {:ok, ambiguous_manifest} = Manifest.add(manifest, duplicate_relative)
    assert :ok = Manifest.write(project, ambiguous_manifest)

    assert {:error, %{code: :ambiguous_reconciliation}} =
             Context.query(root, moved_focus, include: ["intent"])

    assert {:error, %{code: :ambiguous_reconciliation}} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def another(value), do: value",
               apply: true
             )
  end

  test "a SQL constraint failure rolls back store, source, and manifest", %{root: root} do
    assert {:ok, _manifest} = Authoring.init(root)
    assert {:ok, _module} = Authoring.create_module(root, "RavensShop.Pricing", apply: true)

    assert {:ok, function} =
             Authoring.create_function(
               root,
               "RavensShop.Pricing",
               "def total(subtotal, tier), do: subtotal + tier",
               apply: true
             )

    target = function.details.function
    manifest_path = Path.join(root, ".ravens/manifest")
    manifest_before = File.read!(manifest_path)

    assert {:ok, candidate} =
             Authoring.create_module(root, "RavensShop.PricingTest",
               test: true,
               source: "use ExUnit.Case\ntest \"protects pricing\", do: assert(true)",
               for: [target],
               intent: "Protect pricing"
             )

    injected = %{
      candidate
      | evidence: QualificationEvidence.applied(0, 1),
        semantic: %{candidate.semantic | targets: [target, target]}
    }

    assert {:error, %{code: :apply_failed, reason: %{code: :semantic_store_constraint}}} =
             Materializer.apply(injected)

    refute File.exists?(Path.join(root, "test/ravens_shop/pricing_test.exs"))
    assert File.read!(manifest_path) == manifest_before
    assert {:ok, current} = SemanticStore.synchronize(root)
    assert current.status == :current
  end

  test "migrations are idempotent and unsupported newer schemas fail closed", %{root: root} do
    assert {:ok, _manifest} = Authoring.init(root)
    assert {:ok, _manifest} = Authoring.init(root)
    assert {:ok, 1} = SemanticStore.schema_version(root)

    path = Path.join(root, ".ravens/semantic.sqlite3")
    assert {:ok, connection} = Sqlite3.open(path)

    assert :ok =
             Sqlite3.execute(connection, "INSERT INTO schema_migrations VALUES (999, 'later')")

    assert :ok = Sqlite3.close(connection)

    assert {:error, %{code: :unsupported_semantic_schema, found: 999, supported: 1}} =
             SemanticStore.schema_version(root)
  end

  test "stable IDs, semantic keys, and relation identities are constrained", %{root: root} do
    assert {:ok, _manifest} = Authoring.init(root)
    path = Path.join(root, ".ravens/semantic.sqlite3")
    assert {:ok, connection} = Sqlite3.open(path)
    assert :ok = Sqlite3.execute(connection, "PRAGMA foreign_keys = ON")

    assert {:ok, statement} =
             Sqlite3.prepare(connection, "SELECT id FROM semantic_revisions WHERE is_current = 1")

    assert :ok = Sqlite3.bind(statement, [])
    assert {:row, [revision]} = Sqlite3.step(connection, statement)
    assert :ok = Sqlite3.release(connection, statement)

    node_sql = """
    INSERT INTO semantic_nodes(
      entity_id, kind, current_semantic_key, lifecycle, origin, fingerprint,
      created_revision_id, updated_revision_id
    ) VALUES (?, 'module', ?, 'active', 'reconstructed', ?, ?, ?)
    """

    assert :ok =
             run_bound(connection, node_sql, [
               "entity:test-a",
               "module:Test.A",
               "fp-a",
               revision,
               revision
             ])

    assert {:error, _reason} =
             run_bound(connection, node_sql, [
               "entity:test-a",
               "module:Test.B",
               "fp-b",
               revision,
               revision
             ])

    assert {:error, _reason} =
             run_bound(connection, node_sql, [
               "entity:test-b",
               "module:Test.A",
               "fp-b",
               revision,
               revision
             ])

    assert :ok =
             run_bound(connection, node_sql, [
               "entity:test-b",
               "module:Test.B",
               "fp-b",
               revision,
               revision
             ])

    relation_sql = """
    INSERT INTO semantic_relations(
      source_node_id, relation_type, target_node_id, origin, confidence, revision_id,
      identity_key
    ) VALUES (?, 'defines', ?, 'reconstructed', 'derived', ?, ?)
    """

    relation = ["entity:test-a", "entity:test-b", revision, "relation:test"]
    assert :ok = run_bound(connection, relation_sql, relation)
    assert {:error, _reason} = run_bound(connection, relation_sql, relation)
    assert :ok = Sqlite3.close(connection)
  end

  test "origins are fixed and never loaded through dynamic atoms" do
    assert Origin.values() == [
             :requested,
             :source_derived,
             :compiler_confirmed,
             :test_observed,
             :runtime_observed,
             :reconstructed
           ]

    assert {:ok, :requested} = Origin.load("requested")
    assert {:error, %{code: :invalid_semantic_origin}} = Origin.load("invented")
  end

  defp move_and_rename_total(root) do
    pricing_path = Path.join(root, "lib/ravens_shop/pricing.ex")
    moved_relative = "lib/ravens_shop/catalog/pricing.ex"
    moved_path = Path.join(root, moved_relative)
    checkout_path = Path.join(root, "lib/ravens_shop/checkout.ex")

    pricing = File.read!(pricing_path) |> String.replace("def total(", "def final_total(")
    checkout = File.read!(checkout_path) |> String.replace(".total(", ".final_total(")

    File.mkdir_p!(Path.dirname(moved_path))
    File.write!(moved_path, pricing)
    File.rm!(pricing_path)
    File.write!(checkout_path, checkout)

    assert {:ok, project} = Project.open(root)
    assert {:ok, manifest} = Manifest.load(project)

    managed_paths =
      manifest.managed_paths
      |> List.delete("lib/ravens_shop/pricing.ex")
      |> then(&Enum.sort([moved_relative | &1]))

    assert :ok = Manifest.write(project, %{manifest | managed_paths: managed_paths})
    "function:RavensShop.Pricing.final_total/2"
  end

  defp run_cli(mix, arguments) do
    if :os.type() == {:win32, :nt} do
      script =
        Path.join(
          System.tmp_dir!(),
          "ravens-memory-cli-#{System.unique_integer([:positive, :monotonic])}.cmd"
        )

      command = Enum.map_join([mix | arguments], " ", &~s("#{String.replace(&1, "\"", "\"\"")}"))

      try do
        File.write!(script, "@echo off\r\ncall #{command}\r\nexit /b %ERRORLEVEL%\r\n")
        System.cmd("cmd.exe", ["/d", "/c", script], cd: File.cwd!(), stderr_to_stdout: true)
      after
        File.rm(script)
      end
    else
      System.cmd(mix, arguments, cd: File.cwd!(), stderr_to_stdout: true)
    end
  end

  defp run_bound(connection, sql, values) do
    assert {:ok, statement} = Sqlite3.prepare(connection, sql)

    try do
      with :ok <- Sqlite3.bind(statement, values),
           :done <- Sqlite3.step(connection, statement) do
        :ok
      end
    after
      Sqlite3.release(connection, statement)
    end
  end
end
