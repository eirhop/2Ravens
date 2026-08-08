defmodule TwoRavens.ChangeRequestRecoveryTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias TwoRavens.Authoring
  alias TwoRavens.Change
  alias TwoRavens.Change.RequestAttempt
  alias TwoRavens.Change.RequestPatch
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore

  @moduletag timeout: 300_000

  setup do
    root = Path.join(System.tmp_dir!(), "ravens-attempt-#{System.unique_integer([:positive])}")
    mix = System.find_executable("mix") || "mix"

    assert {_output, 0} =
             System.cmd(mix, ["new", root, "--app", "attempt_shop", "--module", "AttemptShop"],
               stderr_to_stdout: true
             )

    assert {:ok, _manifest} = Authoring.init(root)
    on_exit(fn -> File.rm_rf(root) end)

    %{root: root, mix: mix}
  end

  test "JSON Patch applies strict add, remove, replace, and move operations" do
    request = %{
      "operation" => [%{"op" => "create", "text" => "source"}],
      "mode" => "draft_only",
      "temporary" => true
    }

    patch = [
      %{"op" => "move", "from" => "/operation", "path" => "/operations"},
      %{"op" => "add", "path" => "/operations/0/kind", "value" => "source_bundle"},
      %{"op" => "replace", "path" => "/mode", "value" => "apply_if_valid"},
      %{"op" => "remove", "path" => "/temporary"}
    ]

    assert {:ok, repaired} = RequestPatch.apply(request, patch)
    assert repaired["mode"] == "apply_if_valid"

    assert repaired["operations"] == [
             %{"op" => "create", "kind" => "source_bundle", "text" => "source"}
           ]

    refute Map.has_key?(repaired, "operation")
    refute Map.has_key?(repaired, "temporary")

    assert {:error, %{code: :invalid_request_patch, operation: 0}} =
             RequestPatch.apply(request, [
               %{"op" => "move", "from" => "/operation", "path" => "/operation/0/copy"}
             ])
  end

  test "an 8KB malformed bundle is retained and repaired in a fresh process without resending source",
       %{root: root, mix: mix} do
    padding = String.duplicate("lossless request recovery ", 360)

    source = """
    defmodule AttemptShop.Retained do
      @moduledoc #{inspect(padding, limit: :infinity, printable_limit: :infinity)}

      @doc "Returns a stable marker."
      def value, do: :retained
    end
    """

    assert byte_size(source) > 8_000

    malformed = %{
      "mode" => "apply_if_valid",
      "operation" => [
        %{"op" => "create", "kind" => "source_bundle", "text" => source}
      ]
    }

    assert {:error, error} = Change.submit(root, malformed)
    assert error.code == :unknown_request_fields
    assert error.details.fields == ["operation"]
    assert error.details.attempt =~ "attempt:a_"
    assert error.details.attempt_version == 1
    refute File.exists?(Path.join(root, "lib/attempt_shop/retained.ex"))

    assert {:ok, project} = Project.open(root)

    assert {:ok, retained} =
             SemanticStore.get_request_attempt(project, error.details.attempt, 1)

    assert get_in(retained.payload, ["operation", Access.at(0), "text"]) == source

    patch = [%{"op" => "move", "from" => "/operation", "path" => "/operations"}]
    encoded_patch = Jason.encode!(patch)
    assert byte_size(encoded_patch) < 100
    refute encoded_patch =~ "defmodule"
    refute encoded_patch =~ padding

    script = Path.join(root, "retry_attempt.exs")

    File.write!(script, """
    patch = Jason.decode!(System.fetch_env!("RAVENS_RETRY_PATCH"))
    version = System.fetch_env!("RAVENS_ATTEMPT_VERSION") |> String.to_integer()

    case TwoRavens.Change.retry(
           System.fetch_env!("RAVENS_PROJECT_ROOT"),
           System.fetch_env!("RAVENS_ATTEMPT_ID"),
           version,
           patch
         ) do
      {:ok, receipt} -> IO.puts("status=\#{receipt.status} version=\#{version + 1}")
      other -> IO.puts("failure=\#{inspect(other)}")
    end
    """)

    {output, status} =
      System.cmd(mix, ["run", "--no-compile", script],
        cd: File.cwd!(),
        env: [
          {"MIX_ENV", "test"},
          {"RAVENS_PROJECT_ROOT", root},
          {"RAVENS_ATTEMPT_ID", error.details.attempt},
          {"RAVENS_ATTEMPT_VERSION", "1"},
          {"RAVENS_RETRY_PATCH", encoded_patch}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "status=applied version=2"

    written = File.read!(Path.join(root, "lib/attempt_shop/retained.ex"))
    assert written =~ "def value"
    assert written =~ ":retained"

    assert {:ok, latest} =
             SemanticStore.get_request_attempt(project, error.details.attempt, 2)

    assert get_in(latest.payload, ["operations", Access.at(0), "text"]) == source

    assert {:error, stale} = Change.retry(root, error.details.attempt, 1, patch)
    assert stale.code == :stale_request_attempt_version
    assert stale.details.latest == 2
  end

  test "invalid patch does not append a version or mutate accepted source", %{root: root} do
    malformed = %{"mode" => "apply_if_valid", "operation" => []}
    assert {:error, error} = Change.submit(root, malformed)

    patch = [%{"op" => "remove", "path" => "/missing"}]
    assert {:error, failed} = Change.retry(root, error.details.attempt, 1, patch)
    assert failed.code == :invalid_request_patch
    assert failed.details.attempt == error.details.attempt
    assert failed.details.attempt_version == 1

    assert {:ok, project} = Project.open(root)

    assert {:error, %{code: :stale_request_attempt_version, latest: 1}} =
             SemanticStore.get_request_attempt(project, error.details.attempt, 2)

    refute File.exists?(Path.join(root, "lib/attempt_shop/retained.ex"))
  end

  test "migration 4 upgrades an existing store without changing its accepted revision", %{
    root: root
  } do
    assert {:ok, revision_before} = Change.current_revision(root)
    path = Path.join(root, ".ravens/semantic.sqlite3")
    assert {:ok, connection} = Sqlite3.open(path)
    assert :ok = Sqlite3.execute(connection, "DROP TABLE change_request_attempts")
    assert :ok = Sqlite3.execute(connection, "DELETE FROM schema_migrations WHERE version = 4")
    assert :ok = Sqlite3.close(connection)

    assert {:ok, 4} = SemanticStore.schema_version(root)
    assert {:ok, ^revision_before} = Change.current_revision(root)

    assert {:ok, connection} = Sqlite3.open(path)

    assert {:ok, statement} =
             Sqlite3.prepare(
               connection,
               "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?"
             )

    assert :ok = Sqlite3.bind(statement, ["change_request_attempts"])
    assert {:row, [1]} = Sqlite3.step(connection, statement)
    assert :ok = Sqlite3.release(connection, statement)
    assert :ok = Sqlite3.close(connection)
  end

  test "expired attempt cleanup cannot change accepted semantic state", %{root: root} do
    assert {:ok, revision_before} = Change.current_revision(root)
    assert {:ok, project} = Project.open(root)
    assert {:ok, expired} = RequestAttempt.new(%{"mode" => "draft_only"})

    expired = %{
      expired
      | expires_at:
          DateTime.utc_now()
          |> DateTime.add(-60, :second)
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()
    }

    assert {:ok, _expired} = SemanticStore.put_request_attempt(project, expired)

    assert {:error, %{code: :request_attempt_expired}} =
             SemanticStore.get_request_attempt(project, expired.id, expired.version)

    assert {:ok, current} = RequestAttempt.new(%{"mode" => "draft_only"})
    assert {:ok, _current} = SemanticStore.put_request_attempt(project, current)

    assert {:error, %{code: :request_attempt_not_found}} =
             SemanticStore.get_request_attempt(project, expired.id, expired.version)

    assert {:ok, ^revision_before} = Change.current_revision(root)
  end
end
