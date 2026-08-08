defmodule TwoRavens.CLI do
  @moduledoc false

  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Change.Receipt
  alias TwoRavens.Context.Result

  @spec decode_change(String.t()) :: {:ok, map()} | {:error, map()}
  def decode_change(source) when is_binary(source) do
    case Jason.decode(source) do
      {:ok, request} when is_map(request) -> {:ok, request}
      {:ok, _value} -> {:error, %{code: :invalid_change_json, reason: :object_required}}
      {:error, error} -> {:error, %{code: :invalid_change_json, reason: Exception.message(error)}}
    end
  end

  @spec change(Receipt.t()) :: String.t()
  def change(%Receipt{} = receipt) do
    body =
      [
        "status #{receipt.status}",
        "operations #{receipt.operation_count}",
        optional_line("revision", receipt.revision),
        draft_line(receipt),
        count_line("entities", receipt.entities),
        count_line("relationships", receipt.relationships),
        qualification_line(receipt.qualification),
        "affected_paths #{receipt.affected_paths}",
        "working_tree #{if(receipt.working_tree_changed, do: "changed", else: "unchanged")}"
      ] ++ Enum.map(receipt.diagnostics || [], &"diagnostic #{compact_inspect(&1)}")

    body |> Enum.reject(&is_nil/1) |> Enum.join("\n") |> with_output_bytes()
  end

  @spec draft_context(map()) :: String.t()
  def draft_context(context) when is_map(context) do
    entity = context.entity

    [
      "draft #{context.draft} version=#{context.version} status=#{context.status}",
      "entity #{entity.id}",
      list_line("callers", context.callers),
      list_line("callees", context.callees),
      list_line("clauses", context.clauses)
    ]
    |> Kernel.++(Enum.map(context.diagnostics, &"diagnostic #{compact_inspect(&1)}"))
    |> Enum.join("\n")
    |> with_output_bytes()
  end

  @spec revision(String.t()) :: String.t()
  def revision(revision), do: "revision #{revision}" |> with_output_bytes()

  @spec entities([String.t()]) :: String.t()
  def entities(entities) do
    entities
    |> Enum.map_join("\n", &"entity #{&1}")
    |> case do
      "" -> "entities none"
      lines -> lines
    end
    |> with_output_bytes()
  end

  @spec candidate(Candidate.t(), keyword()) :: String.t()
  def candidate(candidate, options \\ [])

  def candidate(%Candidate{} = candidate, options) do
    compact = compact_candidate(candidate)

    if Keyword.get(options, :details, false),
      do: compact <> "\n" <> candidate_details(candidate),
      else: compact
  end

  @spec context(Result.t(), keyword()) :: String.t()
  def context(result, options \\ [])

  def context(%Result{} = result, options) do
    lines = compact_context_lines(result)

    lines =
      if Keyword.get(options, :details, false), do: lines ++ context_details(result), else: lines

    with_output_bytes(Enum.join(lines, "\n"))
  end

  @spec error(map()) :: String.t()
  def error(%{code: code} = reason) do
    details = reason |> plain_map() |> Map.delete(:code) |> inspect(pretty: false, limit: 20)
    "#{code}: #{details}"
  end

  defp draft_line(%Receipt{draft: nil}), do: nil

  defp draft_line(%Receipt{} = receipt),
    do: "draft #{receipt.draft} version=#{receipt.draft_version}"

  defp optional_line(_label, nil), do: nil
  defp optional_line(label, value), do: "#{label} #{value}"

  defp count_line(label, values) when values in [nil, %{}], do: "#{label} none"

  defp count_line(label, values) do
    counts =
      values
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{value}" end)

    "#{label} #{counts}"
  end

  defp qualification_line(nil), do: "qualification unavailable"

  defp qualification_line(qualification) do
    "qualification format=#{qualification.format} compile=#{qualification.compile} " <>
      "tests=#{qualification.tests} commands=#{qualification.commands} " <>
      "output_bytes=#{qualification.output_bytes}"
  end

  defp list_line(label, []), do: "#{label} none"
  defp list_line(label, values), do: "#{label} #{Enum.join(values, " ")}"

  defp compact_inspect(value), do: inspect(value, pretty: false, limit: 20, printable_limit: 500)

  defp plain_map(%{__struct__: _struct} = value), do: Map.from_struct(value)
  defp plain_map(value), do: value

  defp compact_candidate(%Candidate{applied: true} = candidate) do
    receipt = Map.fetch!(candidate.semantic, :receipt)

    [
      "ok #{receipt.operation.id} #{receipt.revision.id}",
      "candidate applied",
      "#{accepted_change(candidate)} #{receipt.entity_id}",
      "derived calls:#{receipt.derived_calls} requested_intents:#{receipt.requested_intents}",
      checks_line(candidate),
      qualification(candidate),
      "working_tree applied"
    ]
    |> Enum.join("\n")
  end

  defp compact_candidate(%Candidate{} = candidate) do
    [
      "ok dry-run",
      "candidate dry-run",
      proposed_change(candidate),
      checks_line(candidate),
      qualification(candidate),
      "working_tree unchanged"
    ]
    |> Enum.join("\n")
  end

  defp accepted_change(%Candidate{kind: :create_module, details: details}),
    do: "added module:#{details.module}"

  defp accepted_change(%Candidate{kind: :create_function, details: details}),
    do: "added #{details.function}"

  defp accepted_change(%Candidate{kind: :set, details: details}),
    do: "changed #{details.direct_impact} operator #{details.from}->#{details.to}"

  defp proposed_change(%Candidate{kind: :create_module, details: details}),
    do: "would add module:#{details.module}"

  defp proposed_change(%Candidate{kind: :create_function, details: details}),
    do: "would add #{details.function}"

  defp proposed_change(%Candidate{kind: :set, details: details}),
    do: "would change #{details.direct_impact} operator #{details.from}->#{details.to}"

  defp checks_line(candidate) do
    evidence = candidate.evidence

    "checks parse=#{evidence.parse},round_trip=#{evidence.round_trip},format=#{evidence.format}," <>
      "compile=#{evidence.compile},test=#{evidence.tests}"
  end

  defp candidate_details(%Candidate{kind: :set} = candidate), do: set_details(candidate)

  defp candidate_details(%Candidate{} = candidate) do
    [
      "details",
      "managed path #{candidate.details.path}",
      "source diff #{candidate.details.changed_lines} line#{plural(candidate.details.changed_lines)}",
      String.trim_trailing(candidate.diff),
      "parse #{candidate.evidence.parse}",
      "round_trip #{candidate.evidence.round_trip}",
      "format #{candidate.evidence.format}",
      "compile #{candidate.evidence.compile}",
      "tests #{candidate.evidence.tests}",
      qualification(candidate)
    ]
    |> Enum.join("\n")
  end

  defp set_details(candidate) do
    details = candidate.details
    boundary = details.boundary

    [
      "details",
      "source diff #{details.changed_lines} line#{plural(details.changed_lines)}",
      String.trim_trailing(candidate.diff),
      "direct impact #{details.direct_impact}",
      impact_line(details.upstream),
      tests_line(details.tests),
      "supported change guard comparison operator",
      "at #{boundary.value} before: #{boundary.left} #{boundary.before} #{boundary.value} #{evaluation(boundary.before_at_boundary)}",
      "at #{boundary.value} after: #{boundary.left} #{boundary.after} #{boundary.value} #{evaluation(boundary.after_at_boundary)}",
      evidence_line("fallback", boundary.fallback),
      evidence_line("boundary test evidence", boundary.test_evidence),
      "parse #{candidate.evidence.parse}",
      "round_trip #{candidate.evidence.round_trip}",
      "compile #{candidate.evidence.compile}",
      "tests #{candidate.evidence.tests}"
    ]
    |> Enum.join("\n")
  end

  defp compact_context_lines(result) do
    revision = String.slice(result.freshness.revision, 0, 12)

    [
      "focus #{result.entity.id} #{result.focus}",
      "revision #{revision}"
    ] ++
      intent_lines(result) ++
      Enum.map(result.caller_relations, fn relation ->
        "caller #{relation.origin} #{relation.semantic_key}"
      end) ++
      Enum.map(result.callee_relations, fn relation ->
        "callee #{relation.origin} #{relation.semantic_key}"
      end) ++
      requested_test_lines(result) ++
      derived_test_lines(result) ++
      evidence_lines(result) ++
      source_lines(result) ++
      [freshness_line(result)] ++
      Enum.map(result.frontier, &"frontier #{&1}")
  end

  defp intent_lines(%Result{} = result) do
    if :intent in result.include, do: included_intent_lines(result), else: []
  end

  defp included_intent_lines(%Result{intents: [_ | _] = intents}) do
    Enum.map(intents, &~s(intent #{&1.origin} "#{escape(&1.text)}"))
  end

  defp included_intent_lines(%Result{
         freshness: %{intent_status: "unavailable", intent_reason: reason}
       }) do
    ["intent unavailable reason=#{reason || :semantic_store_rebuilt_from_source}"]
  end

  defp included_intent_lines(_result), do: ["intent absent"]

  defp requested_test_lines(result) do
    if :tests in result.include do
      Enum.map(result.requested_tests, fn relation ->
        "test requested #{display_subject(relation.semantic_key)} intended_to_test"
      end)
    else
      []
    end
  end

  defp derived_test_lines(result) do
    if :tests in result.include do
      Enum.map(result.derived_test_relations, fn relation ->
        "test #{relation.origin} #{display_subject(relation.semantic_key)} statically_related"
      end)
    else
      []
    end
  end

  defp evidence_lines(result) do
    if :evidence in result.include do
      Enum.map(result.evidence, &evidence_context_line/1)
    else
      []
    end
  end

  defp evidence_context_line(evidence) do
    reason = if evidence.reason, do: " reason=#{evidence.reason}", else: ""
    "evidence #{evidence.origin} #{evidence.type} #{evidence.status}#{reason}"
  end

  defp source_lines(%Result{source: nil}), do: editable_and_clause_lines([])

  defp source_lines(result) do
    ["source", result.source] ++ editable_and_clause_lines(result)
  end

  defp editable_and_clause_lines(%Result{} = result) do
    clauses =
      Enum.map(result.clauses, fn clause ->
        guard = if clause.guard, do: " guard #{clause.guard}", else: ""
        "clause #{clause.ordinal} #{clause.id}#{guard}"
      end)

    editables =
      Enum.map(result.editable_comparisons, fn editable ->
        "editable #{editable.handle}.#{editable.property} #{editable.value}"
      end)

    clauses ++ editables
  end

  defp editable_and_clause_lines(_result), do: []

  defp freshness_line(result) do
    "freshness #{result.freshness.status} #{result.freshness.semantic_revision} " <>
      "scope=managed_files_only"
  end

  defp context_details(result) do
    unsupported =
      case result.unsupported do
        [] -> ["unsupported none in managed source"]
        facts -> Enum.map(facts, &"unsupported #{&1}")
      end

    ["details provenance"] ++ unsupported
  end

  defp with_output_bytes(body), do: stabilize_output_bytes(body, 0)

  defp stabilize_output_bytes(body, previous) do
    output = body <> "\noutput_bytes #{previous}"
    measured = byte_size(output)

    if measured == previous,
      do: output,
      else: stabilize_output_bytes(body, measured)
  end

  defp qualification(candidate),
    do: "qualification #{candidate.evidence.profile} isolated=#{candidate.evidence.isolated}"

  defp evidence_line(label, %{status: :confirmed, reason: reason, clause: clause}),
    do: "#{label} confirmed clause=#{clause} reason=#{reason}"

  defp evidence_line(label, %{status: status, reason: reason}),
    do: "#{label} #{status} reason=#{reason}"

  defp evaluation(%{status: status, reason: reason}), do: "#{status} reason=#{reason}"
  defp evaluation(value), do: value

  defp impact_line([]), do: "upstream impact none"
  defp impact_line(values), do: "upstream impact #{Enum.join(values, " ")}"
  defp tests_line([]), do: "related test none"
  defp tests_line(values), do: "related test #{Enum.join(values, " ")}"

  defp display_subject("module:" <> module), do: module
  defp display_subject("test:" <> rest), do: rest |> String.split(":") |> List.first()
  defp display_subject(value), do: value

  defp escape(value), do: String.replace(value, "\"", "\\\"")
  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
