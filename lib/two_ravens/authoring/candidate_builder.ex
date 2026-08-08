defmodule TwoRavens.Authoring.CandidateBuilder do
  @moduledoc false

  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Diff
  alias TwoRavens.Source.Function

  @spec build(Proposal.t(), TwoRavens.Qualification.Evidence.t()) :: Candidate.t()
  def build(%Proposal{} = proposal, evidence) do
    diffs =
      proposal.files
      |> Enum.sort()
      |> Enum.map_join(fn {path, after_source} ->
        Diff.unified(path, Map.get(proposal.before_files, path, ""), after_source || "")
      end)

    %Candidate{
      kind: proposal.kind,
      root: proposal.project.root,
      files: proposal.files,
      base_hashes: proposal.base_hashes,
      base_working_hash: proposal.base_working_hash,
      manifest: proposal.manifest,
      manifest_hash: proposal.manifest_hash,
      diff: diffs,
      graph: proposal.graph,
      evidence: evidence,
      details:
        proposal
        |> details()
        |> Map.put(:changed_lines, changed_line_count(proposal.before_files, proposal.files)),
      applied: false,
      semantic: proposal.semantic
    }
  end

  defp details(
         %Proposal{kind: :create_function, details: %{function: function_id} = details} = proposal
       ) do
    %Function{} = function = Map.fetch!(proposal.graph.nodes, function_id)

    Map.merge(details, %{
      clauses: Enum.map(function.clauses, & &1.id),
      calls: Enum.flat_map(function.clauses, & &1.calls),
      comparisons: Enum.flat_map(function.clauses, & &1.comparisons)
    })
  end

  defp details(%Proposal{details: details}), do: details

  defp changed_line_count(before_files, after_files) do
    Enum.reduce(after_files, 0, fn {path, after_source}, count ->
      count + Diff.changed_lines(Map.get(before_files, path, ""), after_source || "")
    end)
  end
end
