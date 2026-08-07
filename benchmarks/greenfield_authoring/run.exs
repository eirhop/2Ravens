defmodule TwoRavens.GreenfieldAuthoringBenchmark.Trace do
  @moduledoc false

  defstruct events: []

  def new, do: %__MODULE__{}

  def add(%__MODULE__{} = trace, kind, bytes \\ 0) do
    %{trace | events: [{kind, bytes} | trace.events]}
  end

  def count(%__MODULE__{} = trace, kind),
    do: Enum.count(trace.events, fn {event_kind, _bytes} -> event_kind == kind end)

  def bytes(%__MODULE__{} = trace, kind) do
    trace.events
    |> Enum.filter(fn {event_kind, _bytes} -> event_kind == kind end)
    |> Enum.sum_by(&elem(&1, 1))
  end
end

defmodule TwoRavens.GreenfieldAuthoringBenchmark do
  @moduledoc false

  alias TwoRavens.Authoring
  alias TwoRavens.CLI
  alias TwoRavens.Context
  alias TwoRavens.Diff
  alias TwoRavens.Graph
  alias TwoRavens.GreenfieldAuthoringBenchmark.Trace
  alias TwoRavens.Source

  @pricing """
  defmodule RavensShop.Pricing do
    @moduledoc "Managed module RavensShop.Pricing."
    def discount(subtotal, :vip) when subtotal >= 5_000,
      do: div(subtotal * 10, 100)

    def discount(subtotal, :vip) when subtotal >= 0,
      do: div(subtotal * 5, 100)

    def discount(subtotal, :standard) when subtotal >= 0,
      do: 0

    def total(subtotal, tier), do: subtotal - discount(subtotal, tier)
  end
  """

  @checkout """
  defmodule RavensShop.Checkout do
    @moduledoc "Managed module RavensShop.Checkout."
    def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)
  end
  """

  @tests """
  defmodule RavensShop.PricingTest do
    @moduledoc "Managed ExUnit tests for RavensShop.PricingTest."

    use ExUnit.Case, async: true

    test "prices a VIP checkout" do
      assert RavensShop.Checkout.checkout(6_000, :vip) == 5_400
    end
  end
  """

  @managed_paths [
    "lib/ravens_shop/pricing.ex",
    "lib/ravens_shop/checkout.ex",
    "test/ravens_shop/pricing_test.exs"
  ]

  def run do
    base =
      Path.join(
        System.tmp_dir!(),
        "two-ravens-comparison-#{System.unique_integer([:positive, :monotonic])}"
      )

    ordinary_root = Path.join(base, "ordinary/ravens_shop")
    ravens_root = Path.join(base, "ravens/ravens_shop")

    try do
      bootstrap(ordinary_root)
      bootstrap(ravens_root)
      ordinary = ordinary_condition(ordinary_root)
      ravens = ravens_condition(ravens_root)
      ordinary_source = source_snapshot(ordinary_root)
      ravens_source = source_snapshot(ravens_root)

      source_differences =
        @managed_paths
        |> Enum.filter(&(Map.fetch!(ordinary_source, &1) != Map.fetch!(ravens_source, &1)))
        |> Map.new(fn path ->
          {path,
           Diff.unified(path, Map.fetch!(ordinary_source, path), Map.fetch!(ravens_source, path))}
        end)

      %{
        schema_version: 2,
        tokens: :unavailable,
        equal_final_source: ordinary_source == ravens_source,
        source_differences: source_differences,
        ordinary_files: ordinary,
        two_ravens: ravens
      }
      |> IO.inspect(pretty: true, limit: :infinity)
    after
      File.rm_rf(base)
    end
  end

  defp bootstrap(root) do
    {_output, 0} = mix(["new", root, "--app", "ravens_shop", "--module", "RavensShop"])
  end

  defp ordinary_condition(root) do
    started = System.monotonic_time(:millisecond)
    trace = Trace.new()
    trace = write_source(trace, root, "lib/ravens_shop/pricing.ex", @pricing)
    trace = write_source(trace, root, "lib/ravens_shop/checkout.ex", @checkout)
    trace = write_source(trace, root, "test/ravens_shop/pricing_test.exs", @tests)
    {_format_output, trace} = qualification(trace, root, ["format"])
    {_compile_output, trace} = qualification(trace, root, ["compile", "--warnings-as-errors"])
    {_test_output, trace} = qualification(trace, root, ["test"], test_env())

    trace =
      patch_source(
        trace,
        root,
        "lib/ravens_shop/pricing.ex",
        "subtotal >= 5_000",
        "subtotal > 5_000"
      )

    {_edit_format_output, trace} =
      qualification(trace, root, ["format", "lib/ravens_shop/pricing.ex"])

    {_edit_compile_output, trace} =
      qualification(trace, root, ["compile", "--warnings-as-errors"])

    {_edit_test_output, trace} = qualification(trace, root, ["test"], test_env())
    correct_ms = System.monotonic_time(:millisecond) - started

    metrics(trace, %{
      correction_rounds: 0,
      diff_lines: 1,
      time_to_first_correct_ms: correct_ms,
      compile: :pass,
      tests: :pass,
      incorrect_target_attempts: 0
    })
  end

  defp ravens_condition(root) do
    started = System.monotonic_time(:millisecond)
    trace = Trace.new()
    {:ok, manifest} = Authoring.init(root)
    trace = record_operation(trace, ["init"], inspect(manifest))

    {:ok, pricing_module} = Authoring.create_module(root, "RavensShop.Pricing", apply: true)

    trace =
      record_candidate(
        trace,
        ["create_module", "RavensShop.Pricing", "apply=true"],
        pricing_module
      )

    discount =
      """
      def discount(subtotal, :vip) when subtotal >= 5_000,
        do: div(subtotal * 10, 100)

      def discount(subtotal, :vip) when subtotal >= 0,
        do: div(subtotal * 5, 100)

      def discount(subtotal, :standard) when subtotal >= 0,
        do: 0
      """

    {:ok, discount_candidate} =
      Authoring.create_function(root, "RavensShop.Pricing", discount, apply: true)

    trace =
      record_candidate(
        trace,
        ["create_function", "RavensShop.Pricing", discount, "apply=true"],
        discount_candidate
      )

    total = "def total(subtotal, tier), do: subtotal - discount(subtotal, tier)"

    {:ok, total_candidate} =
      Authoring.create_function(root, "RavensShop.Pricing", total, apply: true)

    trace =
      record_candidate(
        trace,
        ["create_function", "RavensShop.Pricing", total, "apply=true"],
        total_candidate
      )

    {:ok, checkout_module} = Authoring.create_module(root, "RavensShop.Checkout", apply: true)

    trace =
      record_candidate(
        trace,
        ["create_module", "RavensShop.Checkout", "apply=true"],
        checkout_module
      )

    checkout = "def checkout(subtotal, tier), do: RavensShop.Pricing.total(subtotal, tier)"

    {:ok, checkout_candidate} =
      Authoring.create_function(root, "RavensShop.Checkout", checkout, apply: true)

    trace =
      record_candidate(
        trace,
        ["create_function", "RavensShop.Checkout", checkout, "apply=true"],
        checkout_candidate
      )

    test_body =
      """
      use ExUnit.Case, async: true

      test "prices a VIP checkout" do
        assert RavensShop.Checkout.checkout(6_000, :vip) == 5_400
      end
      """

    {:ok, test_candidate} =
      Authoring.create_module(root, "RavensShop.PricingTest",
        test: true,
        source: test_body,
        apply: true
      )

    trace =
      record_candidate(
        trace,
        ["create_test_module", "RavensShop.PricingTest", test_body, "apply=true"],
        test_candidate
      )

    focus = "function:RavensShop.Pricing.discount/2"
    {:ok, context} = Context.query(root, focus, for_edit: true)
    trace = record_operation(trace, ["context", focus, "for_edit=true"], CLI.context(context))
    handle = hd(context.editable_comparisons).handle <> ".operator"
    pricing_path = Path.join(root, "lib/ravens_shop/pricing.ex")
    before_dry_run = File.read!(pricing_path)
    {:ok, dry_set} = Authoring.set(root, handle, ">")
    trace = record_candidate(trace, ["set", handle, ">", "apply=false"], dry_set)
    dry_run_unchanged = File.read!(pricing_path) == before_dry_run
    {:ok, applied_set} = Authoring.set(root, handle, ">", apply: true)
    trace = record_candidate(trace, ["set", handle, ">", "apply=true"], applied_set)
    correct_ms = System.monotonic_time(:millisecond) - started
    {:ok, rebuilt} = Source.rebuild(root)

    metrics(trace, %{
      correction_rounds: 0,
      diff_lines: applied_set.details.changed_lines,
      time_to_first_correct_ms: correct_ms,
      compile: applied_set.evidence.compile,
      tests: applied_set.evidence.tests,
      incorrect_target_attempts: 0,
      dry_run_unchanged: dry_run_unchanged,
      reconstructed_graph_equal:
        Graph.semantic_signature(rebuilt) == Graph.semantic_signature(applied_set.graph)
    })
  end

  defp metrics(trace, details) do
    Map.merge(details, %{
      input_bytes: Trace.bytes(trace, :input),
      output_bytes: Trace.bytes(trace, :surface_output),
      qualification_output_bytes: Trace.bytes(trace, :qualification_output),
      tool_calls: Trace.count(trace, :tool_call),
      qualification_commands: Trace.count(trace, :qualification_command),
      trace_events: length(trace.events)
    })
  end

  defp write_source(trace, root, relative, source) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)

    trace
    |> record_input(["write", relative, source])
    |> Trace.add(:tool_call)
  end

  defp patch_source(trace, root, relative, before_text, after_text) do
    path = Path.join(root, relative)
    before = File.read!(path)
    changed = String.replace(before, before_text, after_text, global: false)
    :ok = File.write(path, changed)

    trace
    |> record_input(["patch", relative, before_text, after_text])
    |> Trace.add(:tool_call)
  end

  defp qualification(trace, root, arguments, environment \\ []) do
    {output, 0} = mix(arguments, root, environment)

    trace =
      trace
      |> record_input(["mix" | arguments])
      |> Trace.add(:tool_call)
      |> Trace.add(:qualification_command)
      |> Trace.add(:surface_output, byte_size(output))
      |> Trace.add(:qualification_output, byte_size(output))

    {output, trace}
  end

  defp record_operation(trace, input, output) do
    trace
    |> record_input(input)
    |> Trace.add(:tool_call)
    |> Trace.add(:surface_output, byte_size(output))
  end

  defp record_candidate(trace, input, candidate) do
    trace = record_operation(trace, input, CLI.candidate(candidate))

    trace =
      Trace.add(trace, :qualification_output, candidate.evidence.output_bytes)

    Enum.reduce(1..candidate.evidence.commands//1, trace, fn _command, traced ->
      Trace.add(traced, :qualification_command)
    end)
  end

  defp record_input(trace, values), do: Trace.add(trace, :input, payload_bytes(values))

  defp payload_bytes(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.intersperse(<<0>>)
    |> IO.iodata_length()
  end

  defp source_snapshot(root) do
    Map.new(@managed_paths, &{&1, File.read!(Path.join(root, &1))})
  end

  defp mix(arguments, root \\ nil, environment \\ []) do
    options = [stderr_to_stdout: true, env: environment]
    options = if root, do: Keyword.put(options, :cd, root), else: options
    System.cmd(System.find_executable("mix") || "mix", arguments, options)
  end

  defp test_env, do: [{"MIX_ENV", "test"}]
end

TwoRavens.GreenfieldAuthoringBenchmark.run()
