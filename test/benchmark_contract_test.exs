defmodule TwoRavens.BenchmarkContractTest do
  use ExUnit.Case, async: true

  @benchmark_dir Path.expand("../benchmarks/ravens_benchmark", __DIR__)
  @greenfield_dir Path.expand("../benchmarks/greenfield_authoring", __DIR__)
  @fixture_dir Path.expand("../dev/benchmark_app", __DIR__)

  setup_all do
    {expected, _binding} = Code.eval_file(Path.join(@benchmark_dir, "expected.exs"))
    {tasks, _binding} = Code.eval_file(Path.join(@benchmark_dir, "tasks.exs"))

    %{expected: expected, tasks: tasks}
  end

  test "the semantic oracle has unique scenarios with complete query inputs", %{
    expected: expected
  } do
    scenario_ids = Enum.map(expected.scenarios, & &1.id)

    assert expected.schema_version == 1
    assert length(scenario_ids) == 10
    assert length(Enum.uniq(scenario_ids)) == length(scenario_ids)

    for scenario <- expected.scenarios do
      assert Map.has_key?(scenario, :purpose)
      assert Map.has_key?(scenario, :expect)

      assert Map.keys(scenario.query) |> Enum.sort() ==
               Enum.sort([:constraints, :focus, :include, :limit, :traversal])
    end
  end

  test "every frozen baseline task has a semantic scenario", %{expected: expected, tasks: tasks} do
    scenario_ids = MapSet.new(expected.scenarios, & &1.id)
    task_scenarios = MapSet.new(tasks, & &1.scenario)

    assert length(tasks) == 8
    assert MapSet.subset?(task_scenarios, scenario_ids)
  end

  test "all declared source ranges exist inside the fixture", %{expected: expected} do
    for {_node, range} <- expected.source_ranges do
      path = Path.join(@fixture_dir, range.file)

      assert File.regular?(path)

      line_count = path |> File.stream!() |> Enum.count()

      assert range.line_start >= 1
      assert range.line_end >= range.line_start
      assert range.line_end <= line_count
    end
  end

  test "the acceptance oracle cannot pollute the analyzed fixture" do
    oracle_path = Path.join(@benchmark_dir, "expected.exs")

    refute String.starts_with?(oracle_path, @fixture_dir)
    refute File.exists?(Path.join(@fixture_dir, "benchmark/expected.exs"))
  end

  test "the greenfield comparison freezes both conditions and honest metrics" do
    {task, _binding} = Code.eval_file(Path.join(@greenfield_dir, "task.exs"))

    assert task.schema_version == 2
    assert Enum.map(task.conditions, & &1.id) == [:ordinary_files, :two_ravens]
    assert task.token_metrics == :record_when_host_exposes_them
    assert task.unmeasured_values == :must_remain_unavailable

    for condition <- task.conditions do
      assert :input_bytes in condition.required_evidence
      assert :output_bytes in condition.required_evidence
      assert :qualification_output_bytes in condition.required_evidence
      assert :qualification_commands in condition.required_evidence
      assert :compile in condition.required_evidence
      assert :tests in condition.required_evidence
      assert :incorrect_target_attempts in condition.required_evidence
    end

    baseline = File.read!(Path.join(@greenfield_dir, "baseline.md"))
    assert baseline =~ "tokens remain `unavailable`"
    assert baseline =~ "no token-saving claim"
  end
end
