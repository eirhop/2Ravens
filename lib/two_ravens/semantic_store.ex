defmodule TwoRavens.SemanticStore do
  @moduledoc "Small public facade for local versioned semantic memory."

  alias TwoRavens.AtomicFile
  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore.Reconciliation
  alias TwoRavens.SemanticStore.SQLite

  @gitignore_path ".ravens/.gitignore"
  @gitignore_entries ["semantic.sqlite3", "semantic.sqlite3-*"]

  @doc "Creates or migrates semantic memory and reconciles it with managed source."
  @spec initialize(Project.t(), Manifest.t()) :: {:ok, map()} | {:error, map()}
  def initialize(%Project{} = project, %Manifest{} = manifest) do
    with :ok <- ensure_gitignore(project) do
      SQLite.with_database(project, fn connection ->
        Reconciliation.ensure_current(connection, project, manifest)
      end)
    end
  end

  @doc "Checks source/store freshness and reconciles only derivable state when needed."
  @spec synchronize(Path.t()) :: {:ok, map()} | {:error, map()}
  def synchronize(root) when is_binary(root) do
    with {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         :ok <- ensure_gitignore(project) do
      SQLite.with_database(project, fn connection ->
        Reconciliation.ensure_current(connection, project, manifest)
      end)
    end
  end

  def synchronize(root), do: {:error, %{code: :invalid_arguments, arguments: %{root: root}}}

  @doc "Returns persisted compact context after a source/store freshness check."
  @spec context(Path.t(), String.t()) :: {:ok, map()} | {:error, map()}
  def context(root, focus) when is_binary(root) and is_binary(focus) do
    with {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         :ok <- ensure_gitignore(project) do
      SQLite.with_database(
        project,
        &context_from_connection(&1, project, manifest, focus)
      )
    end
  end

  def context(root, focus),
    do: {:error, %{code: :invalid_arguments, arguments: %{root: root, focus: focus}}}

  @doc "Runs source materialization and semantic acceptance in one SQLite transaction."
  @spec accept(Project.t(), Candidate.t(), (-> {:ok, TwoRavens.Graph.t()} | {:error, map()})) ::
          {:ok, {TwoRavens.Graph.t(), map()}} | {:error, map()}
  def accept(%Project{} = project, %Candidate{} = candidate, materialize)
      when is_function(materialize, 0) do
    SQLite.with_database(
      project,
      &accept_from_connection(&1, candidate, materialize)
    )
  end

  @doc "Returns the migrated schema version for diagnostics and qualification."
  @spec schema_version(Path.t()) :: {:ok, non_neg_integer()} | {:error, map()}
  def schema_version(root) when is_binary(root) do
    with {:ok, project} <- Project.open(root) do
      SQLite.with_database(project, &SQLite.schema_version/1)
    end
  end

  defp context_from_connection(connection, project, manifest, focus) do
    with {:ok, freshness} <- Reconciliation.ensure_current(connection, project, manifest),
         {:ok, context} <- SQLite.context(connection, focus) do
      {:ok, Map.put(context, :freshness, freshness)}
    end
  end

  defp accept_from_connection(connection, candidate, materialize) do
    with {:ok, current} when not is_nil(current) <- SQLite.current_revision(connection),
         :ok <- verify_base_revision(current, candidate.base_working_hash) do
      SQLite.transaction(
        connection,
        &accept_transaction(&1, candidate, materialize, current.id)
      )
    else
      {:ok, nil} -> {:error, %{code: :semantic_store_empty}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp accept_transaction(connection, candidate, materialize, base_revision) do
    with {:ok, accepted_graph} <- materialize.(),
         {:ok, receipt} <-
           SQLite.persist_acceptance(connection, candidate, accepted_graph, base_revision) do
      {:ok, {accepted_graph, receipt}}
    end
  end

  defp verify_base_revision(%{working_hash: hash}, hash), do: :ok
  defp verify_base_revision(_current, _expected), do: {:error, %{code: :stale_semantic_store}}

  defp ensure_gitignore(project) do
    with {:ok, path} <- Project.resolve_internal(project, @gitignore_path),
         {:ok, existing} <- read_optional(path),
         content <- merge_gitignore(existing),
         {:ok, ^path} <- Project.resolve_internal(project, @gitignore_path),
         :ok <- maybe_write(path, existing, content) do
      :ok
    else
      {:error, %{code: _code} = reason} -> {:error, reason}
      {:error, reason} -> {:error, %{code: :semantic_gitignore_write_failed, reason: reason}}
    end
  end

  defp read_optional(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, %{code: :semantic_gitignore_read_failed, reason: reason}}
    end
  end

  defp merge_gitignore(existing) do
    lines = String.split(existing, ~r/\R/, trim: true)
    additions = Enum.reject(@gitignore_entries, &(&1 in lines))

    (lines ++ additions)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp maybe_write(_path, content, content), do: :ok
  defp maybe_write(path, _existing, content), do: AtomicFile.write(path, content)
end
