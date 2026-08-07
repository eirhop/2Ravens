defmodule TwoRavens.AuthoringSafetyTest do
  use ExUnit.Case, async: true

  alias TwoRavens.Authoring
  alias TwoRavens.Authoring.BoundaryImpact
  alias TwoRavens.Evidence
  alias TwoRavens.Materializer
  alias TwoRavens.Project
  alias TwoRavens.Qualification.Evidence, as: QualificationEvidence
  alias TwoRavens.Source.Comparison
  alias TwoRavens.SourceRange

  setup do
    root =
      Path.join(System.tmp_dir!(), "two-ravens-safety-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "mix.exs"), "defmodule Temporary.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf(root) end)
    %{root: root}
  end

  test "dry runs state exactly which checks were not run", %{root: root} do
    assert {:ok, _manifest} = Authoring.init(root)
    assert {:ok, candidate} = Authoring.create_module(root, "Shop.Pricing")

    assert candidate.evidence.profile == :unqualified_dry_run
    assert candidate.evidence.compile == :not_run
    assert candidate.evidence.tests == :not_run
    assert candidate.evidence.commands == 0
    refute candidate.evidence.isolated
    refute File.exists?(Path.join(root, "lib/shop/pricing.ex"))
  end

  test "invalid public options return structured errors before project access" do
    assert {:error, %{code: :unsupported_options, options: [:unknown]}} =
             Authoring.create_module("missing", "Shop.Pricing", unknown: true)

    assert {:error, %{code: :invalid_option, option: :test, expected: :boolean}} =
             Authoring.create_module("missing", "Shop.Pricing", test: :yes)

    assert {:error, %{code: :duplicate_options, options: [:apply]}} =
             Authoring.create_function("missing", "Shop.Pricing", "def run, do: :ok",
               apply: true,
               apply: false
             )

    assert {:error, %{code: :invalid_arguments}} = Authoring.set(:bad, :bad, :bad)
  end

  test "a post-write graph mismatch restores source and manifest bytes", %{root: root} do
    assert {:ok, _manifest} = Authoring.init(root)
    manifest_path = Path.join(root, ".ravens/manifest")
    manifest_before = File.read!(manifest_path)

    assert {:ok, candidate} = Authoring.create_module(root, "Shop.Pricing")

    injected_failure = %{
      candidate
      | evidence: QualificationEvidence.applied(0, 1),
        graph: %{candidate.graph | nodes: %{}}
    }

    assert {:error, %{code: :accepted_graph_mismatch}} = Materializer.apply(injected_failure)
    refute File.exists?(Path.join(root, "lib/shop/pricing.ex"))
    assert File.read!(manifest_path) == manifest_before
  end

  test "managed paths reject a linked ancestor before any outside write", %{root: root} do
    outside = root <> "-outside"
    link = Path.join(root, "lib/link")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    assert :ok = create_directory_link(outside, link)
    assert {:ok, project} = Project.open(root)

    assert {:error, %{code: :unsafe_managed_path, reason: :symbolic_link}} =
             Project.resolve(project, "lib/link/owned.ex")

    assert {:ok, _manifest} = Authoring.init(root)

    assert {:error, %{code: :unsafe_managed_path}} =
             Authoring.create_module(root, "Link.Owned", apply: true)

    refute File.exists?(Path.join(outside, "owned.ex"))
  end

  test "boundary output distinguishes proved truth from unknown impact" do
    comparison = %Comparison{
      id: "comparison:1",
      function_id: "function:Shop.Pricing.discount/2",
      clause_id: "clause:1",
      clause_fingerprint: "0000000000000000",
      fingerprint: "1111111111111111",
      operator: ">=",
      left: "subtotal",
      right: "5_000",
      source: %SourceRange{
        path: "lib/shop/pricing.ex",
        start_line: 3,
        start_column: 44,
        end_line: 3,
        end_column: 46
      },
      evidence: Evidence.derived_source()
    }

    impact = BoundaryImpact.analyze(comparison, ">")
    assert impact.before_at_boundary == :matches
    assert impact.after_at_boundary == :does_not_match
    assert impact.fallback == %{status: :unknown, reason: :clause_compatibility_not_derived}
    assert impact.test_evidence == %{status: :unknown, reason: :call_argument_flow_not_derived}

    assert BoundaryImpact.analyze(%{comparison | operator: "<"}, "<=").before_at_boundary ==
             :does_not_match

    assert BoundaryImpact.analyze(%{comparison | operator: "<"}, "<=").after_at_boundary ==
             :matches

    assert BoundaryImpact.analyze(%{comparison | operator: "==="}, "!==").before_at_boundary ==
             %{status: :unknown, reason: :operand_types_not_derived}
  end

  defp create_directory_link(target, link) do
    case File.ln_s(target, link) do
      :ok ->
        :ok

      {:error, reason} ->
        if :os.type() == {:win32, :nt},
          do: create_junction(target, link, reason),
          else: {:error, reason}
    end
  end

  defp create_junction(target, link, original_reason) do
    script =
      "New-Item -ItemType Junction -Path $env:RAVENS_TEST_LINK -Target $env:RAVENS_TEST_TARGET | Out-Null"

    case System.cmd(
           "powershell.exe",
           ["-NoProfile", "-NonInteractive", "-Command", script],
           env: [{"RAVENS_TEST_LINK", link}, {"RAVENS_TEST_TARGET", target}],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {original_reason, status, output}}
    end
  end
end
