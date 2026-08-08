defmodule TwoRavens.ChangeEntityAuthoringTest do
  use ExUnit.Case, async: false

  alias TwoRavens.Authoring
  alias TwoRavens.Change
  alias TwoRavens.MCP.Change, as: MCPChange
  alias TwoRavens.Semantic.Revision
  alias TwoRavens.Source

  @moduletag timeout: 300_000

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-change-#{System.unique_integer([:positive])}")
    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(mix, ["new", root, "--app", "entity_shop", "--module", "EntityShop"],
               stderr_to_stdout: true
             )

    assert {:ok, _manifest} = Authoring.init(root)
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "one MCP request creates modules and later operations see earlier entities", %{root: root} do
    request = %{
      "root" => root,
      "commit" => "if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => """
          defmodule EntityShop.Catalog do
            @moduledoc "Provides catalog prices in integer cents."

            @doc "Returns a unit price in integer cents."
            @spec unit_price(atom()) :: non_neg_integer()
            def unit_price(:atlas), do: 2_500
          end

          defmodule EntityShop.Pricing do
            @moduledoc "Calculates merchandise totals in integer cents."
          end
          """
        },
        %{
          "op" => "create",
          "kind" => "function",
          "parent" => "module:EntityShop.Pricing",
          "text" => """
          @doc "Returns a line subtotal in integer cents."
          @spec subtotal(atom(), non_neg_integer()) :: non_neg_integer()
          def subtotal(sku, quantity) do
            EntityShop.Catalog.unit_price(sku) * quantity
          end
          """
        }
      ]
    }

    assert {:ok, receipt} = MCPChange.call(request)
    assert receipt.status == :applied
    assert receipt.operation_count == 2
    assert receipt.affected_paths == 2
    assert receipt.working_tree_changed

    assert File.read!(Path.join(root, "lib/entity_shop/pricing.ex")) =~
             "def subtotal(sku, quantity)"

    assert {:ok, graph} = Source.rebuild(root)
    assert Map.has_key?(graph.nodes, "function:EntityShop.Pricing.subtotal/2")
  end

  test "a failed qualification remains a repairable immutable draft", %{root: root} do
    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    invalid = %{
      "base_revision" => revision,
      "commit" => "if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => """
          defmodule EntityShop.Broken do
            @moduledoc "A candidate retained while its compiler error is repaired."
            def value, do: missing_local()
          end
          """
        }
      ]
    }

    assert {:ok, failed} = Change.submit(root, invalid)
    assert failed.status == :needs_changes
    refute failed.working_tree_changed
    refute File.exists?(Path.join(root, "lib/entity_shop/broken.ex"))

    repair = %{
      "draft" => failed.draft,
      "draft_version" => failed.draft_version,
      "commit" => "if_valid",
      "operations" => [
        %{
          "op" => "replace",
          "target" => "function:EntityShop.Broken.value/0",
          "text" => "def value, do: :ok"
        }
      ]
    }

    assert {:ok, applied} = Change.submit(root, repair)
    assert applied.status == :applied
    assert File.read!(Path.join(root, "lib/entity_shop/broken.ex")) =~ "def value, do: :ok"
  end

  test "multiple clauses retain structural identities when a new clause is inserted", %{
    root: root
  } do
    request = %{
      "commit" => "if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "source_bundle",
          "text" => """
          defmodule EntityShop.Discount do
            @moduledoc "Calculates tier discounts."
            def rate(:vip), do: 10
            def rate(:standard), do: 0
          end
          """
        }
      ]
    }

    assert {:ok, _receipt} = Change.submit(root, request)
    assert {:ok, before_graph} = Source.rebuild(root)
    function = Map.fetch!(before_graph.nodes, "function:EntityShop.Discount.rate/1")
    fallback = List.last(function.clauses)
    first_id = hd(function.clauses).id

    revision = Revision.from_repository(before_graph.revision, :available).id

    add_clause = %{
      "base_revision" => revision,
      "commit" => "if_valid",
      "operations" => [
        %{
          "op" => "create",
          "kind" => "clause",
          "parent" => function.id,
          "before" => fallback.id,
          "text" => "def rate(:partner), do: 8"
        }
      ]
    }

    assert {:ok, _receipt} = Change.submit(root, add_clause)
    assert {:ok, after_graph} = Source.rebuild(root)
    changed = Map.fetch!(after_graph.nodes, function.id)
    assert Enum.map(changed.clauses, & &1.patterns) == [[":vip"], [":partner"], [":standard"]]
    assert hd(changed.clauses).id == first_id
    assert List.last(changed.clauses).id == fallback.id
  end

  test "public validation rejects unknown fields and module replacement", %{root: root} do
    assert {:error, request_error} =
             Change.submit(root, %{
               "commit" => "draft_only",
               "include" => ["source"],
               "operations" => [%{"op" => "delete", "target" => "module:X"}]
             })

    assert request_error.code == :unknown_request_fields

    assert {:error, kind_error} =
             Change.submit(root, %{
               "commit" => "draft_only",
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "module_document",
                   "parent" => "module:X",
                   "text" => "@moduledoc \"X\""
                 }
               ]
             })

    assert kind_error.code == :unsupported_entity_kind

    assert {:error, error} =
             Change.submit(root, %{
               "commit" => "draft_only",
               "operations" => [%{"op" => "delete", "target" => "module:X", "surprise" => true}]
             })

    assert error.code == :unknown_operation_fields

    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    assert {:error, error} =
             Change.submit(root, %{
               "base_revision" => revision,
               "operations" => [
                 %{
                   "op" => "replace",
                   "target" => "module:EntityShop",
                   "text" => "defmodule EntityShop do\nend"
                 }
               ]
             })

    assert error.code in [:entity_not_found, :whole_module_replace_not_allowed]
  end

  test "entity lifecycle operations remain atomic and remove retired projections", %{root: root} do
    assert {:ok, _receipt} =
             Change.submit(root, %{
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule EntityShop.Legacy do
                     @moduledoc "Temporary ownership before an entity move."

                     @doc "Returns its input."
                     def old_name(value), do: value

                     def unused(value), do: value + 0
                   end

                   defmodule EntityShop.Target do
                     @moduledoc "Receives moved entities."
                   end
                   """
                 }
               ]
             })

    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    assert {:ok, receipt} =
             Change.submit(root, %{
               "base_revision" => revision,
               "operations" => [
                 %{
                   "op" => "rename",
                   "target" => "function:EntityShop.Legacy.old_name/1",
                   "to" => "function:EntityShop.Legacy.current_name/1"
                 },
                 %{
                   "op" => "move",
                   "target" => "function:EntityShop.Legacy.current_name/1",
                   "to" => "module:EntityShop.Target"
                 },
                 %{
                   "op" => "delete",
                   "target" => "function:EntityShop.Legacy.unused/1"
                 },
                 %{"op" => "delete", "target" => "module:EntityShop.Legacy", "cascade" => true}
               ]
             })

    assert receipt.status == :applied
    refute File.exists?(Path.join(root, "lib/entity_shop/legacy.ex"))
    target_source = File.read!(Path.join(root, "lib/entity_shop/target.ex"))
    assert target_source =~ "def current_name(value)"
    refute target_source =~ "old_name"
  end

  test "patches are exact and function replacement owns documentation and specifications", %{
    root: root
  } do
    assert {:ok, _receipt} =
             Change.submit(root, %{
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule EntityShop.Amount do
                     @moduledoc "Calculates integer amounts."

                     @doc "Doubles an amount."
                     @spec calculate(integer()) :: integer()
                     def calculate(amount) do
                       amount * 2
                     end
                   end
                   """
                 }
               ]
             })

    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    assert {:ok, _receipt} =
             Change.submit(root, %{
               "base_revision" => revision,
               "operations" => [
                 %{
                   "op" => "patch",
                   "target" => "function:EntityShop.Amount.calculate/1",
                   "diff" => "@@\n-    amount * 2\n+    amount * 3"
                 },
                 %{
                   "op" => "replace",
                   "target" => "function:EntityShop.Amount.calculate/1",
                   "text" => """
                   @doc "Quadruples an amount."
                   @spec calculate(integer()) :: integer()
                   def calculate(amount), do: amount * 4
                   """
                 }
               ]
             })

    source = File.read!(Path.join(root, "lib/entity_shop/amount.ex"))
    assert source =~ "Quadruples an amount"
    assert source =~ "amount * 4"
    refute source =~ "Doubles an amount"
    assert length(Regex.scan(~r/@spec calculate/, source)) == 1
  end

  test "draft context is compact and old immutable versions are rejected", %{root: root} do
    assert {:ok, ready} =
             Change.submit(root, %{
               "commit" => "draft_only",
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule EntityShop.DraftValue do
                     @moduledoc "Holds a draft-only value."
                     def value, do: 1
                   end
                   """
                 }
               ]
             })

    assert ready.status == :ready

    assert {:ok, context} =
             Change.draft_context(
               root,
               ready.draft,
               ready.draft_version,
               "function:EntityShop.DraftValue.value/0"
             )

    assert context.clauses != []
    refute Map.has_key?(context, :source)
    refute File.exists?(Path.join(root, "lib/entity_shop/draft_value.ex"))

    assert {:ok, version_two} =
             Change.submit(root, %{
               "draft" => ready.draft,
               "draft_version" => ready.draft_version,
               "commit" => "draft_only",
               "operations" => [
                 %{
                   "op" => "replace",
                   "target" => "function:EntityShop.DraftValue.value/0",
                   "text" => "def value, do: 2"
                 }
               ]
             })

    assert version_two.draft_version == ready.draft_version + 1

    assert {:error, stale} =
             Change.draft_context(
               root,
               ready.draft,
               ready.draft_version,
               "function:EntityShop.DraftValue.value/0"
             )

    assert stale.code == :stale_draft_version
  end

  test "new module projection places public callers before private helpers", %{root: root} do
    assert {:ok, _receipt} =
             Change.submit(root, %{
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule EntityShop.Ordered do
                     @moduledoc "Demonstrates deterministic caller-first projection."

                     defp helper(value), do: value * 2

                     @doc "Returns a doubled value."
                     def entry(value), do: helper(value)
                   end
                   """
                 }
               ]
             })

    source = File.read!(Path.join(root, "lib/entity_shop/ordered.ex"))
    {entry_position, _length} = :binary.match(source, "def entry")
    {helper_position, _length} = :binary.match(source, "defp helper")
    assert entry_position < helper_position
  end

  test "function and module-form operations cannot cross entity boundaries", %{root: root} do
    assert {:ok, _receipt} =
             Change.submit(root, %{
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "source_bundle",
                   "text" => """
                   defmodule EntityShop.Boundary do
                     @moduledoc "Exercises exact entity boundaries."
                     @compile {:inline, value: 0}
                     def value, do: :ok
                   end
                   """
                 }
               ]
             })

    assert {:ok, graph} = Source.rebuild(root)
    revision = Revision.from_repository(graph.revision, :available).id

    form =
      graph.nodes
      |> Map.values()
      |> Enum.find(&match?(%TwoRavens.Source.ModuleForm{}, &1))

    assert {:ok, change_receipt} =
             Change.submit(root, %{
               "base_revision" => revision,
               "operations" => [
                 %{
                   "op" => "rename",
                   "target" => "function:EntityShop.Boundary.value/0",
                   "to" => "function:EntityShop.Boundary.current_value/0"
                 },
                 %{
                   "op" => "replace",
                   "target" => form.id,
                   "text" => "@compile {:inline, current_value: 0}"
                 }
               ]
             })

    assert change_receipt.status == :applied, inspect(change_receipt)

    assert {:ok, changed_graph} = Source.rebuild(root)
    assert Map.has_key?(changed_graph.nodes, "function:EntityShop.Boundary.current_value/0")
    refute Map.has_key?(changed_graph.nodes, "function:EntityShop.Boundary.value/0")

    changed_form =
      changed_graph.nodes
      |> Map.values()
      |> Enum.find(&match?(%TwoRavens.Source.ModuleForm{}, &1))

    changed_revision = Revision.from_repository(changed_graph.revision, :available).id

    assert {:ok, _receipt} =
             Change.submit(root, %{
               "base_revision" => changed_revision,
               "operations" => [%{"op" => "delete", "target" => changed_form.id}]
             })

    source = File.read!(Path.join(root, "lib/entity_shop/boundary.ex"))
    refute source =~ "@compile"

    assert {:ok, current_graph} = Source.rebuild(root)
    current_revision = Revision.from_repository(current_graph.revision, :available).id

    assert {:error, function_error} =
             Change.submit(root, %{
               "base_revision" => current_revision,
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "function",
                   "parent" => "module:EntityShop.Boundary",
                   "text" => "alias Map, as: Dictionary\ndef injected, do: :ok"
                 }
               ]
             })

    assert function_error.code == :invalid_function_fragment

    assert {:error, form_error} =
             Change.submit(root, %{
               "base_revision" => current_revision,
               "operations" => [
                 %{
                   "op" => "create",
                   "kind" => "module_form",
                   "parent" => "module:EntityShop.Boundary",
                   "text" => "def escaped, do: :not_a_form"
                 }
               ]
             })

    assert form_error.code == :one_module_form_required
  end
end
