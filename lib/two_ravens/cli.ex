defmodule TwoRavens.CLI do
  @moduledoc false

  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Context.Result

  @spec candidate(Candidate.t()) :: String.t()
  def candidate(%Candidate{kind: :set} = candidate), do: set_candidate(candidate)

  def candidate(%Candidate{} = candidate) do
    action = if candidate.applied, do: "applied", else: "dry-run"
    added = added_lines(candidate)

    (["candidate #{action}"] ++
       added ++
       [
         "source diff #{candidate.details.changed_lines} line#{plural(candidate.details.changed_lines)}",
         String.trim_trailing(candidate.diff),
         "parse #{candidate.evidence.parse}",
         "round_trip #{candidate.evidence.round_trip}",
         "format #{candidate.evidence.format}",
         "compile #{candidate.evidence.compile}",
         "tests #{candidate.evidence.tests}",
         qualification(candidate),
         working_tree(candidate)
       ])
    |> Enum.join("\n")
  end

  @spec context(Result.t()) :: String.t()
  def context(%Result{} = result) do
    revision = String.slice(result.freshness.revision, 0, 12)

    clauses =
      Enum.map(result.clauses, fn clause ->
        guard = if clause.guard, do: " guard #{clause.guard}", else: ""

        "clause #{clause.ordinal} #{clause.id}#{guard} " <>
          "source #{clause.source.path}:#{clause.source.start_line}:#{clause.source.start_column}"
      end)

    editables =
      Enum.map(result.editable_comparisons, fn editable ->
        comparison = editable.comparison

        "editable #{editable.handle}.#{editable.property} #{editable.value} " <>
          "source #{comparison.source.path}:#{comparison.source.start_line}:#{comparison.source.start_column}"
      end)

    unsupported =
      case result.unsupported do
        [] -> ["unsupported none in managed source"]
        facts -> Enum.map(facts, &"unsupported #{&1}")
      end

    ([
       "status ok",
       "revision #{revision}",
       "focus #{result.focus}",
       "freshness current managed_files_only indexed=#{result.freshness.indexed_files}",
       "source",
       result.source
     ] ++
       clauses ++
       Enum.map(result.callers, &"caller #{&1}") ++
       Enum.map(result.upstream -- result.callers, &"upstream #{&1}") ++
       Enum.map(result.callees, &"callee #{&1}") ++
       Enum.map(result.tests, &"related test #{&1}") ++
       editables ++ unsupported ++ Enum.map(result.frontier, &"frontier #{&1}"))
    |> Enum.join("\n")
  end

  @spec error(map()) :: String.t()
  def error(%{code: code} = reason) do
    details = reason |> Map.delete(:code) |> inspect(pretty: false, limit: 20)
    "#{code}: #{details}"
  end

  defp set_candidate(candidate) do
    details = candidate.details
    boundary = details.boundary
    action = if candidate.applied, do: "applied", else: "dry-run"

    [
      "candidate #{action}",
      "changed operator #{details.from} -> #{details.to}",
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
      "tests #{candidate.evidence.tests}",
      qualification(candidate),
      working_tree(candidate)
    ]
    |> Enum.join("\n")
  end

  defp added_lines(%Candidate{kind: :create_module, details: details}) do
    ["added module:#{details.module}", "managed path #{details.path}"]
  end

  defp added_lines(%Candidate{kind: :create_function, details: details}) do
    ["added #{details.function}", "managed path #{details.path}"]
  end

  defp impact_line([]), do: "upstream impact none"
  defp impact_line(values), do: "upstream impact #{Enum.join(values, " ")}"
  defp tests_line([]), do: "related test none"
  defp tests_line(values), do: "related test #{Enum.join(values, " ")}"

  defp qualification(candidate),
    do: "qualification #{candidate.evidence.profile} isolated=#{candidate.evidence.isolated}"

  defp evidence_line(label, %{status: :confirmed, reason: reason, clause: clause}),
    do: "#{label} confirmed clause=#{clause} reason=#{reason}"

  defp evidence_line(label, %{status: status, reason: reason}),
    do: "#{label} #{status} reason=#{reason}"

  defp evaluation(%{status: status, reason: reason}), do: "#{status} reason=#{reason}"
  defp evaluation(value), do: value

  defp working_tree(%Candidate{applied: true}), do: "working_tree applied"
  defp working_tree(%Candidate{applied: false}), do: "working_tree unchanged"
  defp plural(1), do: ""
  defp plural(_count), do: "s"
end
