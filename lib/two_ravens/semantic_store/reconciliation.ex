defmodule TwoRavens.SemanticStore.Reconciliation do
  @moduledoc "Reconciles source/store freshness without rewriting requested knowledge."

  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore.SQLite
  alias TwoRavens.Source

  @doc false
  @spec ensure_current(SQLite.connection(), Project.t(), Manifest.t()) ::
          {:ok, map()} | {:error, map()}
  def ensure_current(connection, %Project{} = project, %Manifest{} = manifest) do
    with {:ok, source_revision} <- Source.revision(project, manifest),
         {:ok, stored_revision} <- SQLite.current_revision(connection) do
      reconcile(connection, project, manifest, source_revision, stored_revision)
    end
  end

  defp reconcile(_connection, _project, _manifest, source, %{working_hash: hash} = stored)
       when source.working_hash == hash do
    {:ok,
     %{
       status: :current,
       revision: stored,
       source: :semantic_store,
       graph_rebuilt: false,
       unresolved: []
     }}
  end

  defp reconcile(connection, project, manifest, _source, nil) do
    with {:ok, graph} <- rebuild(project, manifest),
         {:ok, snapshot} <-
           SQLite.transaction(connection, fn connection ->
             SQLite.persist_snapshot(
               connection,
               graph,
               :reconstructed,
               :unavailable,
               :semantic_store_rebuilt_from_source
             )
           end) do
      {:ok,
       %{
         status: status(graph, :reconstructed),
         revision: revision_map(snapshot.revision),
         source: :managed_source,
         graph_rebuilt: true,
         unresolved: graph.unsupported
       }}
    end
  end

  defp reconcile(connection, project, manifest, _source, stored) do
    intent_status = load_intent_status(stored.intent_status)

    with {:ok, graph} <- rebuild(project, manifest),
         {:ok, snapshot} <-
           SQLite.transaction(connection, fn connection ->
             SQLite.persist_snapshot(
               connection,
               graph,
               :source_derived,
               intent_status,
               stored.reason
             )
           end) do
      {:ok,
       %{
         status: status(graph, :reconciled),
         revision: revision_map(snapshot.revision),
         source: :managed_source,
         graph_rebuilt: true,
         unresolved: graph.unsupported
       }}
    end
  end

  defp rebuild(project, manifest) do
    case Source.rebuild(project, manifest) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, %{code: :ambiguous_identity} = reason} ->
        {:error, Map.put(reason, :code, :ambiguous_reconciliation)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp status(%{unsupported: []}, status), do: status
  defp status(_graph, _status), do: :unresolved

  defp load_intent_status("available"), do: :available
  defp load_intent_status("unavailable"), do: :unavailable

  defp revision_map(revision) do
    %{
      id: revision.id,
      working_hash: revision.working_hash,
      git_revision: revision.git_revision,
      intent_status: Atom.to_string(revision.intent_status),
      reason: revision.reason
    }
  end
end
