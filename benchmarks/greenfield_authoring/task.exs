%{
  schema_version: 2,
  id: :greenfield_semantic_authoring_mvp,
  completion_rule:
    "formatted source compiles, tests pass, and the intended one-token edit is applied",
  conditions: [
    %{
      id: :ordinary_files,
      method: "ordinary file creation and patching",
      required_evidence: [
        :input_bytes,
        :output_bytes,
        :qualification_output_bytes,
        :tool_calls,
        :qualification_commands,
        :correction_rounds,
        :diff_lines,
        :time_to_first_correct_ms,
        :compile,
        :tests,
        :incorrect_target_attempts
      ]
    },
    %{
      id: :two_ravens,
      method: "2Ravens creation, context, and semantic set",
      required_evidence: [
        :input_bytes,
        :output_bytes,
        :qualification_output_bytes,
        :tool_calls,
        :qualification_commands,
        :correction_rounds,
        :diff_lines,
        :time_to_first_correct_ms,
        :compile,
        :tests,
        :incorrect_target_attempts
      ]
    }
  ],
  token_metrics: :record_when_host_exposes_them,
  unmeasured_values: :must_remain_unavailable,
  measurement_rules: %{
    bootstrap: "create the ordinary Mix project before timing and event collection",
    input_bytes: "UTF-8 bytes supplied to authoring and verification operations",
    output_bytes: "UTF-8 bytes returned at the author-facing operation boundary",
    qualification_output_bytes: "compiler, formatter, and test subprocess output bytes",
    tool_calls: "author-facing operations derived from recorded events",
    qualification_commands: "formatter, compiler, and test subprocesses derived from events",
    timing_endpoint: "the final edit has passed required checks, before diagnostic reconstruction"
  },
  frozen_change: %{from: ">=", to: ">", boundary: "5_000"}
}
