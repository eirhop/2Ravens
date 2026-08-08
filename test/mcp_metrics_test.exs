defmodule TwoRavens.MCPMetricsTest do
  use ExUnit.Case, async: false

  alias TwoRavens.MCP.Metrics

  @environment "TWO_RAVENS_METRICS_FILE"

  test "opt-in event metrics count repeated source without recording its content" do
    path =
      Path.join(System.tmp_dir!(), "ravens-metrics-#{System.unique_integer([:positive])}.jsonl")

    previous = System.get_env(@environment)
    System.put_env(@environment, path)

    on_exit(fn ->
      restore_environment(previous)
      File.rm(path)
    end)

    source = "defmodule SecretProbe do\n  def value, do: :secret_value\nend"
    arguments = %{"operations" => [%{"op" => "create", "text" => source}]}
    result = {:ok, %{status: :applied, qualification: %{tests: :pass}}}

    assert :ok = Metrics.record("ravens_change", arguments, result, 12)
    assert :ok = Metrics.record("ravens_change", arguments, result, 10)

    [first, second] =
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert first["source_bytes"] == byte_size(source)
    assert first["repeated_source_bytes"] == 0
    assert second["repeated_source_bytes"] == byte_size(source)
    assert first["qualification_count"] == 1
    assert first["operation_count"] == 1

    contents = File.read!(path)
    refute contents =~ "SecretProbe"
    refute contents =~ "secret_value"
  end

  test "events expose repair and selector outcomes without payload content" do
    path =
      Path.join(System.tmp_dir!(), "ravens-metrics-#{System.unique_integer([:positive])}.jsonl")

    previous = System.get_env(@environment)
    System.put_env(@environment, path)

    on_exit(fn ->
      restore_environment(previous)
      File.rm(path)
    end)

    arguments = %{
      "attempt" => "attempt:a_private",
      "attempt_version" => 1,
      "patch" => [%{"op" => "remove", "path" => "/unexpected"}]
    }

    result =
      {:ok,
       %{
         status: :applied,
         selected: [
           %{
             warnings: [%{code: :unsupported_selector_includes}],
             omitted: true
           }
         ]
       }}

    assert :ok = Metrics.record("ravens_retry", arguments, result, 4)

    event = path |> File.read!() |> String.trim() |> Jason.decode!()

    assert event["operation_count"] == 1
    assert event["request_repair_count"] == 1
    assert event["draft_repair_count"] == 0
    assert event["selector_correction_count"] == 1
    assert event["selector_omission_count"] == 1

    contents = File.read!(path)
    refute contents =~ "a_private"
    refute contents =~ "/unexpected"
  end

  defp restore_environment(nil), do: System.delete_env(@environment)
  defp restore_environment(value), do: System.put_env(@environment, value)
end
