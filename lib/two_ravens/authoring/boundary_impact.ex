defmodule TwoRavens.Authoring.BoundaryImpact do
  @moduledoc "Conservative boundary evidence for a comparison-operator candidate."

  alias TwoRavens.Source.Comparison

  @enforce_keys [
    :value,
    :left,
    :before,
    :after,
    :before_at_boundary,
    :after_at_boundary,
    :fallback,
    :test_evidence
  ]
  defstruct [
    :value,
    :left,
    :before,
    :after,
    :before_at_boundary,
    :after_at_boundary,
    :fallback,
    :test_evidence
  ]

  @type truth :: :matches | :does_not_match
  @type unknown :: %{status: :unknown, reason: atom()}
  @type evidence ::
          unknown()
          | %{status: :absent, reason: atom()}
          | %{status: :present, reason: atom()}
          | %{status: :confirmed, reason: atom(), clause: String.t()}
  @type t :: %__MODULE__{
          value: String.t(),
          left: String.t(),
          before: String.t(),
          after: String.t(),
          before_at_boundary: truth() | unknown(),
          after_at_boundary: truth() | unknown(),
          fallback: evidence(),
          test_evidence: evidence()
        }

  @doc "Describes only facts proven by equality at the edited comparison boundary."
  @spec analyze(Comparison.t(), String.t(), map()) :: t()
  def analyze(%Comparison{} = comparison, operator, evidence \\ %{}) do
    %__MODULE__{
      value: comparison.right,
      left: comparison.left,
      before: comparison.operator,
      after: operator,
      before_at_boundary: truth_at_equal_operands(comparison.operator),
      after_at_boundary: truth_at_equal_operands(operator),
      fallback:
        Map.get(evidence, :fallback, %{
          status: :unknown,
          reason: :clause_compatibility_not_derived
        }),
      test_evidence:
        Map.get(evidence, :test_evidence, %{
          status: :unknown,
          reason: :call_argument_flow_not_derived
        })
    }
  end

  defp truth_at_equal_operands(operator) when operator in ["==", "<=", ">="],
    do: :matches

  defp truth_at_equal_operands(operator) when operator in ["===", "!=="],
    do: %{status: :unknown, reason: :operand_types_not_derived}

  defp truth_at_equal_operands(_operator), do: :does_not_match
end
