defmodule TwoRavens.SemanticMemoryBenchmark do
  @moduledoc false

  alias TwoRavens.Authoring
  alias TwoRavens.CLI
  alias TwoRavens.Context
  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Source

  @tasks Code.eval_file(Path.join(__DIR__, "tasks.exs")) |> elem(0)
  @expected Code.eval_file(Path.join(__DIR__, "expected.exs")) |> elem(0)

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

  @initial_focus "function:RavensShop.Pricing.total/2"
  @renamed_focus "function:RavensShop.Pricing.final_total/2"
  @managed_paths [
    "lib/ravens_shop/pricing.ex",
    "lib/ravens_shop/checkout.ex",
    "test/ravens_shop/pricing_test.exs"
  ]

  def run do
    base =
      Path.join(
        System.tmp_dir!(),
        "two-ravens-semantic-memory-#{System.unique_integer([:positive, :monotonic])}"
      )

    roots = %{
      files_only: Path.join(base, "files_only/ravens_shop"),
      source_indexed: Path.join(base, "source_indexed/ravens_shop"),
      semantic_memory: Path.join(base, "semantic_memory/ravens_shop")
    }

    try do
      Enum.each(roots, fn {_condition, root} -> bootstrap(root) end)
      semantic_creation = semantic_fixture(roots.semantic_memory)
      source_snapshot = source_snapshot(roots.semantic_memory, @managed_paths)
      files_creation = ordinary_fixture(roots.files_only, source_snapshot, false)
      indexed_creation = ordinary_fixture(roots.source_indexed, source_snapshot, true)
      equivalent_initial_source = equivalent_source?(roots)

      results = %{
        files_only: run_condition(:files_only, roots.files_only, files_creation, nil),
        source_indexed:
          run_condition(:source_indexed, roots.source_indexed, indexed_creation, nil),
        semantic_memory:
          run_condition(
            :semantic_memory,
            roots.semantic_memory,
            semantic_creation.metrics,
            semantic_creation.entity_id
          )
      }

      recovery = recovery_probe(roots.semantic_memory)

      report = %{
        schema_version: 1,
        tokens: :unavailable,
        controls: @tasks.controls,
        frozen_tasks: Enum.map(@tasks.tasks, & &1.id),
        equivalent_initial_source: equivalent_initial_source,
        conditions: results,
        recovery: recovery,
        break_even: break_even(results),
        decision: decision(results)
      }

      IO.inspect(report, pretty: true, limit: :infinity, width: 120)
      report
    after
      File.rm_rf(base)
    end
  end

  defp bootstrap(root) do
    {_output, 0} = mix(["new", root, "--app", "ravens_shop", "--module", "RavensShop"])
  end

  defp semantic_fixture(root) do
    started = System.monotonic_time(:millisecond)
    {:ok, manifest} = Authoring.init(root)
    events = [event(:tool, ["init"], inspect(manifest))]

    {events, _candidate} =
      semantic_operation(events, ["create_module", "Pricing"], fn ->
        Authoring.create_module(root, "RavensShop.Pricing", apply: true)
      end)

    {events, _candidate} =
      semantic_operation(events, ["create_function", "discount", @discount], fn ->
        Authoring.create_function(root, "RavensShop.Pricing", @discount, apply: true)
      end)

    {events, total} =
      semantic_operation(events, ["create_function", "total"], fn ->
        Authoring.create_function(
          root,
          "RavensShop.Pricing",
          "def total(subtotal, tier), do: subtotal - discount(subtotal, tier)",
          intent: "Calculate final price after the tier discount",
          apply: true
        )
      end)

    {events, _candidate} =
      semantic_operation(events, ["create_module", "Checkout"], fn ->
        Authoring.create_module(root, "RavensShop.Checkout", apply: true)
      end)

    {events, _candidate} =
      semantic_operation(events, ["create_function", "checkout"], fn ->
        Authoring.create_function(
          root,
          "RavensShop.Checkout",
          "def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)",
          apply: true
        )
      end)

    {events, _candidate} =
      semantic_operation(events, ["create_test", @test_body, @initial_focus], fn ->
        Authoring.create_module(root, "RavensShop.PricingTest",
          test: true,
          source: @test_body,
          for: [@initial_focus],
          intent: "Protect VIP checkout pricing",
          apply: true
        )
      end)

    %{
      entity_id: total.semantic.receipt.entity_id,
      metrics: creation_metrics(events, System.monotonic_time(:millisecond) - started)
    }
  end

  defp semantic_operation(events, request, operation) do
    {:ok, candidate} = operation.()
    output = CLI.candidate(candidate)
    qualification = candidate.evidence.output_bytes

    event =
      event(:tool, request, output)
      |> Map.put(:qualification_output_bytes, qualification)
      |> Map.put(:subprocesses, candidate.evidence.commands)

    {[event | events], candidate}
  end

  defp ordinary_fixture(root, snapshot, indexed?) do
    started = System.monotonic_time(:millisecond)

    write_events =
      Enum.map(snapshot, fn {path, source} ->
        absolute = Path.join(root, path)
        File.mkdir_p!(Path.dirname(absolute))
        File.write!(absolute, source)
        event(:write, [path, source], "ok")
      end)

    manifest_events = if indexed?, do: [create_manifest(root)], else: []
    {format_output, 0} = mix(["format"], root)

    {verify_output, 0} =
      mix(
        ["do", "compile", "--warnings-as-errors", "+", "test", "--no-compile"],
        root,
        [{"MIX_ENV", "test"}]
      )

    qualification_events = [
      event(:qualification, ["mix", "format"], format_output),
      event(:qualification, ["mix", "do", "compile", "test"], verify_output)
    ]

    creation_metrics(
      write_events ++ manifest_events ++ qualification_events,
      System.monotonic_time(:millisecond) - started
    )
  end

  defp create_manifest(root) do
    {:ok, project} = Project.open(root)
    {:ok, manifest} = Manifest.init(project)

    manifest =
      Enum.reduce(@managed_paths, manifest, fn path, current ->
        {:ok, updated} = Manifest.add(current, path)
        updated
      end)

    :ok = Manifest.write(project, manifest)
    event(:tool, ["manifest", @managed_paths], inspect(manifest))
  end

  defp run_condition(condition, root, creation, original_entity) do
    {tasks, _entity} =
      Enum.map_reduce(@tasks.tasks, original_entity, fn task, entity ->
        if task[:transition] == :move_and_rename_total, do: move_and_rename_total(root, condition)

        focus =
          if task[:transition] == :move_and_rename_total or task.id == :review_behavior,
            do: @renamed_focus,
            else: @initial_focus

        {measurement, next_entity} = measure_task(condition, root, task, focus, entity)
        {measurement, next_entity}
      end)

    cumulative = cumulative(tasks, creation.context_bytes)

    %{
      creation: creation,
      tasks: tasks,
      checkpoints: Map.take(cumulative, @tasks.checkpoints),
      final_cumulative_context_bytes: cumulative[length(tasks)],
      correct_tasks: Enum.count(tasks, & &1.correct),
      total_tasks: length(tasks)
    }
  end

  defp measure_task(condition, root, task, focus, original_entity) do
    started = System.monotonic_time(:millisecond)

    {result, facts, operations, current_entity} =
      task_context(condition, root, task, focus, original_entity)

    expected = Map.fetch!(@expected.tasks, task.id)
    required_recall = Enum.count(expected.required, &(&1 in facts))
    forbidden_recall = Enum.count(expected.forbidden, &(&1 in facts))
    correct = required_recall == length(expected.required) and forbidden_recall == 0
    request_bytes = byte_size(task.prompt)
    result_bytes = byte_size(result)

    measurement =
      Map.merge(operations, %{
        id: task.id,
        model_tokens: :unavailable,
        tool_request_bytes: request_bytes,
        tool_result_bytes: result_bytes,
        context_bytes: request_bytes + result_bytes,
        stored_facts_reused: if(condition == :semantic_memory, do: length(facts), else: 0),
        corrections: 0,
        incorrect_assumptions: if(correct, do: 0, else: 1),
        required_recall: required_recall,
        required_total: length(expected.required),
        forbidden_recall: forbidden_recall,
        correct: correct,
        wall_time_ms: System.monotonic_time(:millisecond) - started
      })

    {measurement, current_entity}
  end

  defp task_context(:semantic_memory, root, task, focus, original_entity) do
    {:ok, context} = Context.query(root, focus, include: task.include)
    result = CLI.context(context)
    facts = semantic_facts(context, focus, original_entity)

    operations = %{
      searches: 0,
      listings: 0,
      source_reads: length(@managed_paths),
      semantic_queries: 1
    }

    {result, facts, operations, context.entity.id}
  end

  defp task_context(:source_indexed, root, task, focus, original_entity) do
    {:ok, graph} = Source.rebuild(root)
    facts = derived_facts(graph, focus, task.include, original_entity)
    result = Enum.join(Enum.sort(facts), "\n")

    operations = %{
      searches: 0,
      listings: 0,
      source_reads: map_size(graph.fragments),
      semantic_queries: 0
    }

    {result, facts, operations, nil}
  end

  defp task_context(:files_only, root, task, focus, original_entity) do
    sources = Enum.map(task.files, &File.read!(Path.join(root, &1)))
    result = Enum.join(sources, "\n--- file ---\n")
    facts = file_facts(sources, focus, original_entity)
    operations = %{searches: 1, listings: 0, source_reads: length(sources), semantic_queries: 0}
    {result, facts, operations, nil}
  end

  defp semantic_facts(context, focus, original_entity) do
    []
    |> add_if(context.intents != [], "intent:calculate_final_price_after_tier_discount")
    |> add_if(context.callers != [], "caller:function:RavensShop.Checkout.checkout/2")
    |> add_if(context.requested_tests != [], "test:requested:RavensShop.PricingTest")
    |> add_if(context.tests != [], "test:derived:RavensShop.PricingTest")
    |> add_if(
      Enum.any?(context.evidence, &(&1.type == "function_coverage" and &1.status == "unknown")),
      "coverage:unknown"
    )
    |> add_if(
      not is_nil(original_entity) and context.entity.id == original_entity,
      "identity:preserved"
    )
    |> then(&["focus:#{focus}" | &1])
  end

  defp derived_facts(graph, focus, include, _original_entity) do
    case Graph.function(graph, focus) do
      {:ok, _function} ->
        []
        |> add_if(
          "callers" in include and Graph.callers(graph, focus) != [],
          "caller:function:RavensShop.Checkout.checkout/2"
        )
        |> add_if(
          "tests" in include and Graph.related_tests(graph, focus) != [],
          "test:derived:RavensShop.PricingTest"
        )
        |> add_if("evidence" in include, "coverage:unknown")
        |> then(&["focus:#{focus}" | &1])

      {:error, _reason} ->
        []
    end
  end

  defp file_facts(sources, focus, _original_entity) do
    source = Enum.join(sources, "\n")
    call = if focus == @initial_focus, do: "Pricing.total", else: "Pricing.final_total"

    []
    |> add_if(String.contains?(source, call), "caller:function:RavensShop.Checkout.checkout/2")
    |> add_if(
      String.contains?(source, "prices a VIP checkout"),
      "test:derived:RavensShop.PricingTest"
    )
    |> add_if(String.contains?(source, "test \""), "coverage:unknown")
    |> add_if(String.contains?(source, function_name(focus)), "focus:#{focus}")
  end

  defp move_and_rename_total(root, condition) do
    old_relative = "lib/ravens_shop/pricing.ex"
    new_relative = "lib/ravens_shop/catalog/pricing.ex"
    old_path = Path.join(root, old_relative)
    new_path = Path.join(root, new_relative)
    checkout_path = Path.join(root, "lib/ravens_shop/checkout.ex")

    pricing = File.read!(old_path) |> String.replace("def total(", "def final_total(")
    checkout = File.read!(checkout_path) |> String.replace(".total(", ".final_total(")
    File.mkdir_p!(Path.dirname(new_path))
    File.write!(new_path, pricing)
    File.rm!(old_path)
    File.write!(checkout_path, checkout)

    if condition != :files_only do
      {:ok, project} = Project.open(root)
      {:ok, manifest} = Manifest.load(project)

      paths =
        manifest.managed_paths
        |> List.delete(old_relative)
        |> then(&Enum.sort([new_relative | &1]))

      :ok = Manifest.write(project, %{manifest | managed_paths: paths})
    end
  end

  defp recovery_probe(root) do
    warm_started = System.monotonic_time(:millisecond)

    {:ok, warm_context} =
      Context.query(root, @renamed_focus, include: ["intent", "callers", "tests", "evidence"])

    warm_output = CLI.context(warm_context)
    warm_ms = System.monotonic_time(:millisecond) - warm_started
    cold_root = Path.join(Path.dirname(root), "cold_recovery")

    try do
      {:ok, _copied} = File.cp_r(root, cold_root)
      remove_store_files(cold_root)
      cold_started = System.monotonic_time(:millisecond)

      {:ok, cold_context} =
        Context.query(cold_root, @renamed_focus,
          include: ["intent", "callers", "tests", "evidence"]
        )

      cold_output = CLI.context(cold_context)

      %{
        warm_query: %{
          tool_result_bytes: byte_size(warm_output),
          wall_time_ms: warm_ms,
          graph_rebuilt: warm_context.freshness.graph_rebuilt,
          intent_status: warm_context.freshness.intent_status
        },
        cold_store_reconstruction: %{
          tool_result_bytes: byte_size(cold_output),
          wall_time_ms: System.monotonic_time(:millisecond) - cold_started,
          graph_rebuilt: cold_context.freshness.graph_rebuilt,
          intent_status: cold_context.freshness.intent_status,
          requested_intents_recovered: length(cold_context.intents)
        }
      }
    after
      File.rm_rf(cold_root)
    end
  end

  defp remove_store_files(root) do
    root
    |> Path.join(".ravens/semantic.sqlite3*")
    |> Path.wildcard()
    |> Enum.each(&File.rm!/1)
  end

  defp creation_metrics(events, wall_time_ms) do
    %{
      tool_request_bytes: Enum.sum_by(events, & &1.request_bytes),
      tool_result_bytes: Enum.sum_by(events, & &1.result_bytes),
      context_bytes: Enum.sum_by(events, &(&1.request_bytes + &1.result_bytes)),
      tool_calls: length(events),
      qualification_output_bytes:
        Enum.sum_by(events, &Map.get(&1, :qualification_output_bytes, 0)),
      subprocesses:
        Enum.sum_by(
          events,
          &Map.get(&1, :subprocesses, if(&1.kind == :qualification, do: 1, else: 0))
        ),
      wall_time_ms: wall_time_ms
    }
  end

  defp event(kind, request, result) do
    request = request |> inspect(limit: :infinity) |> byte_size()
    %{kind: kind, request_bytes: request, result_bytes: byte_size(result)}
  end

  defp cumulative(tasks, creation_bytes) do
    tasks
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, creation_bytes}, fn {task, index}, {values, total} ->
      total = total + task.context_bytes
      {Map.put(values, index, total), total}
    end)
    |> elem(0)
  end

  defp break_even(results) do
    %{
      versus_files_only: first_break_even(results.semantic_memory, results.files_only),
      versus_source_indexed: first_break_even(results.semantic_memory, results.source_indexed)
    }
  end

  defp first_break_even(semantic, comparator) do
    Enum.find(@tasks.checkpoints, :none, fn checkpoint ->
      semantic.checkpoints[checkpoint] <= comparator.checkpoints[checkpoint]
    end)
  end

  defp decision(results) do
    break_even = break_even(results)

    %{
      preserves_unique_requested_knowledge:
        results.semantic_memory.correct_tasks > results.source_indexed.correct_tasks,
      correctness_not_reduced:
        results.semantic_memory.correct_tasks >= results.files_only.correct_tasks and
          results.semantic_memory.correct_tasks >= results.source_indexed.correct_tasks,
      reaches_files_break_even: break_even.versus_files_only != :none,
      reaches_source_index_break_even: break_even.versus_source_indexed != :none,
      gate: if(break_even.versus_source_indexed == :none, do: :fail, else: :pass)
    }
  end

  defp equivalent_source?(roots) do
    snapshots =
      Enum.map(roots, fn {_condition, root} -> source_snapshot(root, @managed_paths) end)

    Enum.uniq(snapshots) |> length() == 1
  end

  defp source_snapshot(root, paths), do: Map.new(paths, &{&1, File.read!(Path.join(root, &1))})
  defp add_if(values, true, value), do: [value | values]
  defp add_if(values, false, _value), do: values
  defp function_name(@initial_focus), do: "def total("
  defp function_name(@renamed_focus), do: "def final_total("

  defp mix(arguments, root \\ nil, environment \\ []) do
    options = [stderr_to_stdout: true, env: environment]
    options = if root, do: Keyword.put(options, :cd, root), else: options
    System.cmd(System.find_executable("mix") || "mix", arguments, options)
  end
end

TwoRavens.SemanticMemoryBenchmark.run()
