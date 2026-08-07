defmodule TwoRavens.Authoring.Pipeline do
  @moduledoc false

  alias TwoRavens.Authoring.CandidateBuilder
  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Materializer
  alias TwoRavens.Qualification.Evidence
  alias TwoRavens.Qualifier
  alias TwoRavens.Qualifier.Result

  @spec finish(Proposal.t(), boolean()) ::
          {:ok, TwoRavens.Authoring.Candidate.t()} | {:error, map()}
  def finish(%Proposal{kind: kind} = proposal, false)
      when kind in [:create_module, :create_function] do
    {:ok, CandidateBuilder.build(proposal, Evidence.unqualified_dry_run())}
  end

  def finish(%Proposal{kind: :set} = proposal, false),
    do: qualify(proposal, :qualified_dry_run)

  def finish(%Proposal{} = proposal, true) do
    with {:ok, candidate} <- qualify(proposal, :apply) do
      Materializer.apply(candidate)
    end
  end

  defp qualify(proposal, profile) do
    with {:ok, %Result{} = qualified} <-
           Qualifier.qualify(
             proposal.project,
             proposal.manifest,
             proposal.files,
             proposal.graph,
             profile
           ) do
      proposal = %{proposal | files: qualified.files, graph: qualified.graph}
      {:ok, CandidateBuilder.build(proposal, qualified.evidence)}
    end
  end
end
