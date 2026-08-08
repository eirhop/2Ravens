%{
  schema_version: 1,
  id: :semantic_memory_lifecycle_mvp,
  completion_rule: "return every required fact without any forbidden claim",
  controls: %{
    model: :same_model_when_agent_run,
    reasoning_effort: :same_effort_when_agent_run,
    permissions: :same_permissions,
    prompts: :identical_across_conditions,
    unavailable_metrics: :remain_unavailable
  },
  conditions: [:files_only, :source_indexed, :semantic_memory],
  checkpoints: [1, 3, 5, 6],
  tasks: [
    %{
      id: :explain_intent,
      prompt: "Explain why the shared pricing total exists.",
      include: ["intent"],
      files: ["lib/ravens_shop/pricing.ex"]
    },
    %{
      id: :identify_callers,
      prompt: "Identify every managed caller of the shared pricing total.",
      include: ["callers"],
      files: ["lib/ravens_shop/pricing.ex", "lib/ravens_shop/checkout.ex"]
    },
    %{
      id: :separate_test_meaning,
      prompt: "Separate intended test protection, static test relation, and observed coverage.",
      include: ["tests", "evidence"],
      files: [
        "lib/ravens_shop/pricing.ex",
        "lib/ravens_shop/checkout.ex",
        "test/ravens_shop/pricing_test.exs"
      ]
    },
    %{
      id: :change_impact,
      prompt: "Report callers and tests affected by changing the shared pricing total.",
      include: ["callers", "tests"],
      files: [
        "lib/ravens_shop/pricing.ex",
        "lib/ravens_shop/checkout.ex",
        "test/ravens_shop/pricing_test.exs"
      ]
    },
    %{
      id: :continue_after_rename,
      prompt: "Continue from the same entity after its source move and rename.",
      include: ["intent", "callers", "tests", "evidence"],
      files: [
        "lib/ravens_shop/catalog/pricing.ex",
        "lib/ravens_shop/checkout.ex",
        "test/ravens_shop/pricing_test.exs"
      ],
      transition: :move_and_rename_total
    },
    %{
      id: :review_behavior,
      prompt: "Review the renamed pricing behavior with intent, callers, tests, and evidence.",
      include: ["intent", "callers", "tests", "evidence"],
      files: [
        "lib/ravens_shop/catalog/pricing.ex",
        "lib/ravens_shop/checkout.ex",
        "test/ravens_shop/pricing_test.exs"
      ]
    }
  ]
}
