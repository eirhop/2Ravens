defmodule TwoRavens.SemanticMemoryBenchmarkContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @benchmark Path.join(@root, "benchmarks/semantic_memory")

  test "the frozen lifecycle has three conditions, six tasks, and required checkpoints" do
    {contract, _binding} = Code.eval_file(Path.join(@benchmark, "tasks.exs"))

    assert contract.schema_version == 1
    assert contract.conditions == [:files_only, :source_indexed, :semantic_memory]
    assert contract.checkpoints == [1, 3, 5, 6]
    assert length(contract.tasks) == 6
    assert Enum.map(contract.tasks, & &1.id) == Enum.uniq(Enum.map(contract.tasks, & &1.id))

    prompts = Enum.map(contract.tasks, & &1.prompt)
    assert Enum.all?(prompts, &(is_binary(&1) and byte_size(&1) > 20))

    assert Enum.any?(contract.tasks, &("intent" in &1.include))

    assert Enum.any?(contract.tasks, &(&1[:transition] == :move_and_rename_total))
  end

  test "the external oracle covers every task and forbids invented provenance" do
    {contract, _binding} = Code.eval_file(Path.join(@benchmark, "tasks.exs"))
    {oracle, _binding} = Code.eval_file(Path.join(@benchmark, "expected.exs"))

    assert oracle.oracle_location == :outside_analyzed_projects

    assert Map.keys(oracle.tasks) |> Enum.sort() ==
             Enum.map(contract.tasks, & &1.id) |> Enum.sort()

    assert "intent:inferred" in oracle.tasks.explain_intent.forbidden
    assert "coverage:observed" in oracle.tasks.separate_test_meaning.forbidden
    assert "identity:preserved" in oracle.tasks.continue_after_rename.required
  end

  test "the event recorder derives bytes, correctness, and break-even" do
    source = File.read!(Path.join(@benchmark, "run.exs"))

    for required <- [
          "creation_metrics(events",
          "tool_request_bytes",
          "tool_result_bytes",
          "context_bytes",
          "required_recall",
          "first_break_even",
          "tokens: :unavailable"
        ] do
      assert source =~ required
    end
  end
end
