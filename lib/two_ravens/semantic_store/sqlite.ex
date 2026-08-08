defmodule TwoRavens.SemanticStore.SQLite do
  @moduledoc "Low-level Exqlite boundary using short-lived connections and bound SQL."

  alias Exqlite.Sqlite3
  alias TwoRavens.Project
  alias TwoRavens.Repository
  alias TwoRavens.Semantic.Entity
  alias TwoRavens.Semantic.Operation
  alias TwoRavens.Semantic.Origin
  alias TwoRavens.Semantic.Revision
  alias TwoRavens.SemanticStore.Migration
  alias TwoRavens.SemanticStore.Projection

  @relative_path ".ravens/semantic.sqlite3"
  @type connection :: reference()

  @doc false
  @spec with_database(Project.t(), (connection() -> {:ok, term()} | {:error, map()})) ::
          {:ok, term()} | {:error, map()}
  def with_database(%Project{} = project, fun) when is_function(fun, 1) do
    with {:ok, path} <- Project.resolve_internal(project, @relative_path),
         :ok <- ensure_parent(path),
         {:ok, ^path} <- Project.resolve_internal(project, @relative_path),
         {:ok, connection} <- open(path) do
      result =
        try do
          with :ok <- configure(connection),
               :ok <- migrate(connection) do
            fun.(connection)
          end
        rescue
          error -> sqlite_error(error)
        catch
          kind, reason -> sqlite_error({kind, reason})
        end

      close_result = Sqlite3.close(connection)
      combine_close(result, close_result)
    end
  end

  @doc false
  @spec transaction(connection(), (connection() -> {:ok, term()} | {:error, map()})) ::
          {:ok, term()} | {:error, map()}
  def transaction(connection, fun) when is_function(fun, 1) do
    with :ok <- execute_static(connection, "BEGIN IMMEDIATE") do
      result =
        try do
          fun.(connection)
        rescue
          error -> sqlite_error(error)
        catch
          kind, reason -> sqlite_error({kind, reason})
        end

      finish_transaction(connection, result)
    end
  end

  @doc false
  @spec current_revision(connection()) :: {:ok, map() | nil} | {:error, map()}
  def current_revision(connection) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT id, working_hash, git_revision, intent_status, reconstruction_reason
             FROM semantic_revisions WHERE is_current = 1
             """,
             []
           ) do
      case rows do
        [] ->
          {:ok, nil}

        [[id, working_hash, git_revision, intent_status, reason]] ->
          {:ok,
           %{
             id: id,
             working_hash: working_hash,
             git_revision: git_revision,
             intent_status: intent_status,
             reason: load_reason(reason)
           }}

        _ ->
          {:error, %{code: :semantic_store_corrupt, reason: :multiple_current_revisions}}
      end
    end
  end

  @doc false
  @spec persist_snapshot(connection(), TwoRavens.Graph.t(), Origin.t(), atom(), atom() | nil) ::
          {:ok, map()} | {:error, map()}
  def persist_snapshot(connection, graph, origin, intent_status, reason \\ nil) do
    revision = Revision.from_repository(graph.revision, intent_status, reason)
    nodes = Projection.nodes(graph)

    with :ok <- upsert_revision(connection, revision),
         {:ok, assigned} <- assign_entities(connection, nodes, revision, origin),
         :ok <- replace_derived_snapshot(connection, revision.id),
         :ok <- insert_projections(connection, nodes, assigned, revision.id, origin),
         :ok <- insert_derived_relations(connection, graph, assigned, revision.id, origin),
         :ok <- insert_source_evidence(connection, graph, nodes, assigned, revision.id, origin) do
      {:ok, %{revision: revision, entities: assigned}}
    end
  end

  @doc false
  @spec persist_acceptance(
          connection(),
          TwoRavens.Authoring.Candidate.t(),
          TwoRavens.Graph.t(),
          String.t()
        ) :: {:ok, map()} | {:error, map()}
  def persist_acceptance(connection, candidate, graph, base_revision_id) do
    with {:ok, snapshot} <-
           persist_snapshot(connection, graph, :source_derived, :available),
         operation <-
           Operation.accepted(
             candidate.kind,
             base_revision_id,
             snapshot.revision.id,
             operation_result(candidate)
           ),
         :ok <- insert_operation(connection, operation),
         {:ok, subject_id} <- subject_entity(candidate, snapshot.entities),
         :ok <- insert_intent(connection, candidate, subject_id, operation, snapshot.revision),
         :ok <-
           insert_requested_relations(
             connection,
             candidate,
             subject_id,
             snapshot.entities,
             snapshot.revision,
             operation
           ),
         :ok <-
           insert_qualification_evidence(
             connection,
             candidate,
             subject_id,
             operation,
             snapshot.revision
           ),
         {:ok, stored_signature} <- stored_signature(connection, snapshot.revision.id),
         true <- stored_signature == Projection.signature(graph) do
      {:ok,
       %{
         operation: operation,
         revision: snapshot.revision,
         entity_id: subject_id,
         derived_calls: Enum.count(graph.edges, &(&1.kind == :calls)),
         requested_intents: if(candidate.semantic.intent, do: 1, else: 0)
       }}
    else
      false -> {:error, %{code: :stored_graph_mismatch}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec stored_signature(connection(), String.t()) :: {:ok, term()} | {:error, map()}
  def stored_signature(connection, revision_id) do
    with {:ok, nodes} <-
           query(
             connection,
             """
             SELECT n.kind, n.current_semantic_key, p.fingerprint
             FROM source_projections p
             JOIN semantic_nodes n ON n.entity_id = p.node_id
             WHERE p.revision_id = ?
             ORDER BY n.current_semantic_key
             """,
             [revision_id]
           ),
         {:ok, relations} <-
           query(
             connection,
             """
             SELECT r.relation_type, source.current_semantic_key, target.current_semantic_key
             FROM semantic_relations r
             JOIN semantic_nodes source ON source.entity_id = r.source_node_id
             JOIN semantic_nodes target ON target.entity_id = r.target_node_id
             WHERE r.revision_id = ? AND r.origin IN ('source_derived', 'reconstructed')
             ORDER BY r.relation_type, source.current_semantic_key, target.current_semantic_key,
                      r.source_path, r.start_line, r.start_column
             """,
             [revision_id]
           ) do
      {:ok, {Enum.map(nodes, &List.to_tuple/1), Enum.map(relations, &List.to_tuple/1)}}
    end
  end

  @doc false
  @spec context(connection(), String.t()) :: {:ok, map()} | {:error, map()}
  def context(connection, focus) do
    with {:ok, revision} when not is_nil(revision) <- current_revision(connection),
         {:ok, entity} <- find_current_entity(connection, revision.id, focus),
         {:ok, intents} <- load_intents(connection, entity.id),
         {:ok, callers} <- load_related(connection, revision.id, entity.id, :callers),
         {:ok, callees} <- load_related(connection, revision.id, entity.id, :callees),
         {:ok, derived_tests} <- load_related(connection, revision.id, entity.id, :derived_tests),
         {:ok, requested_tests} <-
           load_related(connection, revision.id, entity.id, :requested_tests),
         {:ok, evidence} <- load_evidence(connection, revision.id, entity.id),
         {:ok, frontier} <- load_frontier(connection, revision.id) do
      {:ok,
       %{
         entity: entity,
         revision: revision,
         intents: intents,
         callers: callers,
         callees: callees,
         derived_tests: derived_tests,
         requested_tests: requested_tests,
         evidence: evidence,
         frontier: frontier
       }}
    else
      {:ok, nil} -> {:error, %{code: :semantic_store_empty}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec schema_version(connection()) :: {:ok, non_neg_integer()} | {:error, map()}
  def schema_version(connection), do: applied_version(connection)

  defp ensure_parent(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> :ok
      {:error, reason} -> sqlite_error(reason)
    end
  end

  defp open(path) do
    case Sqlite3.open(path) do
      {:ok, connection} -> {:ok, connection}
      {:error, reason} -> sqlite_error(reason)
    end
  end

  defp configure(connection) do
    with :ok <- execute_static(connection, "PRAGMA foreign_keys = ON"),
         :ok <- execute_static(connection, "PRAGMA busy_timeout = 5000") do
      execute_static(connection, "PRAGMA journal_mode = DELETE")
    end
  end

  defp migrate(connection) do
    with :ok <-
           execute_static(
             connection,
             """
             CREATE TABLE IF NOT EXISTS schema_migrations (
               version INTEGER PRIMARY KEY,
               applied_at TEXT NOT NULL
             ) STRICT
             """
           ),
         {:ok, version} <- applied_version(connection) do
      cond do
        version > Migration.current_version() ->
          {:error,
           %{
             code: :unsupported_semantic_schema,
             found: version,
             supported: Migration.current_version()
           }}

        version == Migration.current_version() ->
          :ok

        true ->
          migrate_forward(connection, version + 1)
      end
    end
  end

  defp applied_version(connection) do
    with {:ok, rows} <-
           query(connection, "SELECT COALESCE(MAX(version), 0) FROM schema_migrations", []) do
      case rows do
        [[version]] when is_integer(version) -> {:ok, version}
        _ -> {:error, %{code: :semantic_store_corrupt, reason: :invalid_schema_version}}
      end
    end
  end

  defp migrate_forward(connection, next_version) do
    transaction(connection, &migrate_versions(&1, next_version))
    |> case do
      {:ok, :migrated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp migrate_versions(connection, next_version) do
    Enum.reduce_while(next_version..Migration.current_version(), {:ok, :migrated}, fn version,
                                                                                      _acc ->
      case apply_migration(connection, version) do
        :ok -> {:cont, {:ok, :migrated}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_migration(connection, version) do
    with :ok <- execute_migration_statements(connection, Migration.statements(version)) do
      execute_bound(
        connection,
        "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
        [version, DateTime.utc_now() |> DateTime.to_iso8601()]
      )
    end
  end

  defp execute_migration_statements(connection, statements) do
    Enum.reduce_while(statements, :ok, fn statement, :ok ->
      case execute_static(connection, statement) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_revision(connection, %Revision{} = revision) do
    with :ok <- execute_bound(connection, "UPDATE semantic_revisions SET is_current = 0", []) do
      execute_bound(
        connection,
        """
        INSERT INTO semantic_revisions(
          id, working_hash, git_revision, created_at, is_current, intent_status,
          reconstruction_reason
        ) VALUES (?, ?, ?, ?, 1, ?, ?)
        ON CONFLICT(working_hash) DO UPDATE SET
          git_revision = excluded.git_revision,
          is_current = 1,
          intent_status = excluded.intent_status,
          reconstruction_reason = excluded.reconstruction_reason
        """,
        [
          revision.id,
          revision.working_hash,
          revision.git_revision,
          revision.created_at,
          Atom.to_string(revision.intent_status),
          dump_reason(revision.reason)
        ]
      )
    end
  end

  defp assign_entities(connection, nodes, revision, origin) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT entity_id, kind, current_semantic_key, fingerprint
             FROM semantic_nodes WHERE lifecycle = 'active'
             """,
             []
           ),
         active <-
           Enum.map(rows, fn [id, kind, semantic_key, fingerprint] ->
             %{id: id, kind: kind, semantic_key: semantic_key, fingerprint: fingerprint}
           end),
         {:ok, assignments} <- reconcile_assignments(nodes, active, origin),
         :ok <- write_assignments(connection, assignments, revision, origin),
         :ok <- retire_unmatched(connection, active, assignments) do
      {:ok, Map.new(assignments, &{&1.node.semantic_key, &1.entity_id})}
    end
  end

  defp reconcile_assignments(nodes, active, origin) do
    new_keys = MapSet.new(nodes, & &1.semantic_key)

    Enum.reduce_while(nodes, {:ok, [], MapSet.new()}, fn node, state ->
      reconcile_node(node, state, active, new_keys, origin)
    end)
    |> case do
      {:ok, assignments, _used} -> {:ok, Enum.reverse(assignments)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reconcile_node(node, {:ok, assignments, used}, active, new_keys, origin) do
    case matching_entity(node, active, new_keys, used) do
      {:ambiguous, ids} ->
        {:halt,
         {:error,
          %{
            code: :ambiguous_identity_reconciliation,
            semantic_key: node.semantic_key,
            candidates: Enum.sort(ids)
          }}}

      existing ->
        assignment = assignment(node, existing, origin)
        used = MapSet.put(used, assignment.entity_id)
        {:cont, {:ok, [assignment | assignments], used}}
    end
  end

  defp matching_entity(node, active, new_keys, used) do
    exact =
      Enum.find(
        active,
        &(&1.semantic_key == node.semantic_key and not MapSet.member?(used, &1.id))
      )

    exact || unique_candidate(rename_candidates(node, active, new_keys, used))
  end

  defp rename_candidates(node, active, new_keys, used) do
    Enum.filter(active, fn existing ->
      existing.kind == node.kind and existing.fingerprint == node.fingerprint and
        not MapSet.member?(used, existing.id) and
        not MapSet.member?(new_keys, existing.semantic_key)
    end)
  end

  defp assignment(node, nil, origin) do
    %{node: node, entity_id: new_entity_id(origin, node), new?: true}
  end

  defp assignment(node, existing, _origin) do
    %{node: node, entity_id: existing.id, new?: false}
  end

  defp unique_candidate([]), do: nil
  defp unique_candidate([candidate]), do: candidate
  defp unique_candidate(candidates), do: {:ambiguous, Enum.map(candidates, & &1.id)}

  defp new_entity_id(:reconstructed, node),
    do: Entity.reconstructed_id(node.kind, node.semantic_key)

  defp new_entity_id(_origin, _node), do: Entity.generate_id()

  defp write_assignments(connection, assignments, revision, origin) do
    Enum.reduce_while(assignments, :ok, fn assignment, :ok ->
      result =
        if assignment.new? do
          execute_bound(
            connection,
            """
            INSERT INTO semantic_nodes(
              entity_id, kind, current_semantic_key, lifecycle, origin, fingerprint,
              created_revision_id, updated_revision_id
            ) VALUES (?, ?, ?, 'active', ?, ?, ?, ?)
            """,
            [
              assignment.entity_id,
              assignment.node.kind,
              assignment.node.semantic_key,
              Origin.dump(origin),
              assignment.node.fingerprint,
              revision.id,
              revision.id
            ]
          )
        else
          execute_bound(
            connection,
            """
            UPDATE semantic_nodes
            SET current_semantic_key = ?, lifecycle = 'active', fingerprint = ?,
                updated_revision_id = ?
            WHERE entity_id = ?
            """,
            [
              assignment.node.semantic_key,
              assignment.node.fingerprint,
              revision.id,
              assignment.entity_id
            ]
          )
        end

      case result do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp retire_unmatched(connection, active, assignments) do
    assigned = MapSet.new(assignments, & &1.entity_id)

    active
    |> Enum.reject(&MapSet.member?(assigned, &1.id))
    |> Enum.reduce_while(:ok, fn entity, :ok ->
      case execute_bound(
             connection,
             "UPDATE semantic_nodes SET lifecycle = 'retired' WHERE entity_id = ?",
             [entity.id]
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp replace_derived_snapshot(connection, revision_id) do
    with :ok <-
           execute_bound(connection, "DELETE FROM source_projections WHERE revision_id = ?", [
             revision_id
           ]),
         :ok <-
           execute_bound(
             connection,
             """
             DELETE FROM semantic_relations
             WHERE revision_id = ? AND origin IN ('source_derived', 'reconstructed')
             """,
             [revision_id]
           ) do
      execute_bound(
        connection,
        "DELETE FROM semantic_evidence WHERE revision_id = ? AND operation_id IS NULL",
        [revision_id]
      )
    end
  end

  defp insert_projections(connection, nodes, assigned, revision_id, origin) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      range = node.source

      case execute_bound(
             connection,
             """
             INSERT INTO source_projections(
               node_id, revision_id, managed_path, start_line, start_column, end_line,
               end_column, content_hash, fingerprint, origin
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             """,
             [
               Map.fetch!(assigned, node.semantic_key),
               revision_id,
               range.path,
               range.start_line,
               range.start_column,
               range.end_line,
               range.end_column,
               node.content_hash,
               node.fingerprint,
               Origin.dump(origin)
             ]
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_derived_relations(connection, graph, assigned, revision_id, origin) do
    graph
    |> Projection.relations()
    |> Enum.reduce_while(:ok, fn relation, :ok ->
      range = relation.range
      path = if range, do: range.path, else: ""
      line = if range, do: range.start_line, else: 0
      column = if range, do: range.start_column, else: 0

      values = [
        Map.fetch!(assigned, relation.source),
        relation.type,
        Map.fetch!(assigned, relation.target),
        Origin.dump(origin),
        "derived",
        revision_id,
        path,
        line,
        column
      ]

      case insert_relation(connection, values) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_relation(connection, values) do
    identity_key = Repository.hash(:erlang.term_to_binary(values))

    execute_bound(
      connection,
      """
      INSERT INTO semantic_relations(
        source_node_id, relation_type, target_node_id, origin, confidence, revision_id,
        source_path, start_line, start_column, identity_key
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      values ++ [identity_key]
    )
  end

  defp insert_source_evidence(connection, graph, nodes, assigned, revision_id, origin) do
    node_result =
      Enum.reduce_while(nodes, :ok, fn node, :ok ->
        case insert_node_evidence(connection, node, assigned, revision_id, origin) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    with :ok <- node_result do
      insert_unresolved_evidence(connection, graph.unsupported, revision_id, origin)
    end
  end

  defp insert_node_evidence(connection, node, assigned, revision_id, origin) do
    subject = Map.fetch!(assigned, node.semantic_key)

    with :ok <-
           insert_evidence(
             connection,
             subject,
             nil,
             "source_projection",
             "pass",
             Origin.dump(origin),
             revision_id,
             nil
           ) do
      maybe_insert_coverage_unknown(connection, node, subject, revision_id)
    end
  end

  defp insert_unresolved_evidence(connection, unsupported, revision_id, origin) do
    Enum.reduce_while(unsupported, :ok, fn reason, :ok ->
      result =
        insert_evidence(
          connection,
          nil,
          nil,
          "unresolved_source",
          "unknown",
          Origin.dump(origin),
          revision_id,
          reason
        )

      reduce_result(result)
    end)
  end

  defp maybe_insert_coverage_unknown(connection, %{kind: "function"}, subject, revision_id) do
    insert_evidence(
      connection,
      subject,
      nil,
      "function_coverage",
      "unknown",
      "test_observed",
      revision_id,
      "coverage_not_captured"
    )
  end

  defp maybe_insert_coverage_unknown(_connection, _node, _subject, _revision_id), do: :ok

  defp insert_operation(connection, operation) do
    execute_bound(
      connection,
      """
      INSERT INTO semantic_operations(
        operation_id, requested_action, base_revision_id, result_revision_id, result,
        status, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        operation.id,
        Atom.to_string(operation.action),
        operation.base_revision,
        operation.result_revision,
        operation.result,
        Atom.to_string(operation.status),
        operation.created_at
      ]
    )
  end

  defp subject_entity(candidate, assigned) do
    case Map.fetch(assigned, candidate.semantic.subject) do
      {:ok, entity_id} ->
        {:ok, entity_id}

      :error ->
        {:error, %{code: :semantic_subject_not_found, subject: candidate.semantic.subject}}
    end
  end

  defp insert_intent(_connection, %{semantic: %{intent: nil}}, _subject, _operation, _revision),
    do: :ok

  defp insert_intent(connection, candidate, subject, operation, revision) do
    execute_bound(
      connection,
      """
      INSERT INTO semantic_intents(
        subject_node_id, intent_text, intent_kind, operation_id, revision_id, origin
      ) VALUES (?, ?, ?, ?, ?, 'requested')
      """,
      [
        subject,
        candidate.semantic.intent,
        Atom.to_string(candidate.semantic.intent_kind),
        operation.id,
        revision.id
      ]
    )
  end

  defp insert_requested_relations(
         connection,
         candidate,
         subject_id,
         assigned,
         revision,
         _operation
       ) do
    Enum.reduce_while(candidate.semantic.targets, :ok, fn target, :ok ->
      result = insert_requested_relation(connection, target, subject_id, assigned, revision.id)
      reduce_result(result)
    end)
  end

  defp insert_requested_relation(connection, target, subject_id, assigned, revision_id) do
    with {:ok, target_id} <- fetch_target(assigned, target) do
      insert_relation(connection, [
        subject_id,
        "intended_to_test",
        target_id,
        "requested",
        "asserted",
        revision_id,
        "",
        0,
        0
      ])
    end
  end

  defp fetch_target(assigned, target) do
    case Map.fetch(assigned, target) do
      {:ok, target_id} -> {:ok, target_id}
      :error -> {:error, %{code: :semantic_target_not_found, target: target}}
    end
  end

  defp reduce_result(:ok), do: {:cont, :ok}
  defp reduce_result({:error, reason}), do: {:halt, {:error, reason}}

  defp insert_qualification_evidence(connection, candidate, subject, operation, revision) do
    evidence = candidate.evidence

    [
      {"parse", evidence.parse, "source_derived"},
      {"round_trip", evidence.round_trip, "source_derived"},
      {"format", evidence.format, "compiler_confirmed"},
      {"compile", evidence.compile, "compiler_confirmed"},
      {"test_suite", evidence.tests, "test_observed"},
      {"accepted_graph", :pass, "source_derived"}
    ]
    |> Enum.reduce_while(:ok, fn {type, status, origin}, :ok ->
      case insert_evidence(
             connection,
             subject,
             operation.id,
             type,
             Atom.to_string(status),
             origin,
             revision.id,
             nil
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_evidence(
         connection,
         subject,
         operation,
         type,
         status,
         origin,
         revision,
         reason
       ) do
    values = [subject, operation, type, status, origin, revision, reason]
    identity_key = Repository.hash(:erlang.term_to_binary(values))

    execute_bound(
      connection,
      """
      INSERT INTO semantic_evidence(
        subject_node_id, operation_id, evidence_type, status, origin, revision_id,
        reason, identity_key
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      values ++ [identity_key]
    )
  end

  defp operation_result(candidate) do
    candidate.semantic.subject || Atom.to_string(candidate.kind)
  end

  defp find_current_entity(connection, revision_id, focus) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT entity_id, kind, current_semantic_key, lifecycle, origin
             FROM semantic_nodes
             WHERE updated_revision_id = ? AND current_semantic_key = ? AND lifecycle = 'active'
             """,
             [revision_id, focus]
           ) do
      case rows do
        [[id, kind, semantic_key, lifecycle, origin]] ->
          {:ok,
           %{id: id, kind: kind, semantic_key: semantic_key, lifecycle: lifecycle, origin: origin}}

        [] ->
          {:error, %{code: :function_not_found, focus: focus}}

        _ ->
          {:error, %{code: :ambiguous_identity, focus: focus}}
      end
    end
  end

  defp load_intents(connection, subject) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT DISTINCT i.intent_text, i.intent_kind, i.origin, i.revision_id, i.operation_id
             FROM semantic_intents i
             WHERE i.subject_node_id = ?
             ORDER BY i.id DESC
             """,
             [subject]
           ) do
      {:ok,
       Enum.map(rows, fn [text, kind, origin, revision, operation] ->
         %{text: text, kind: kind, origin: origin, revision: revision, operation: operation}
       end)}
    end
  end

  defp load_related(connection, revision_id, entity_id, direction) do
    {sql, parameters} = related_query(direction, revision_id, entity_id)

    with {:ok, rows} <- query(connection, sql, parameters) do
      {:ok,
       Enum.map(rows, fn [entity, kind, semantic_key, relation, origin, confidence] ->
         %{
           entity_id: entity,
           kind: kind,
           semantic_key: semantic_key,
           relation: relation,
           origin: origin,
           confidence: confidence
         }
       end)}
    end
  end

  defp related_query(:callers, revision, entity) do
    {
      """
      SELECT source.entity_id, source.kind, source.current_semantic_key,
             r.relation_type, r.origin, r.confidence
      FROM semantic_relations r
      JOIN semantic_nodes source ON source.entity_id = r.source_node_id
      WHERE r.revision_id = ? AND r.target_node_id = ? AND r.relation_type = 'calls'
        AND r.origin IN ('source_derived', 'reconstructed')
      ORDER BY source.current_semantic_key
      """,
      [revision, entity]
    }
  end

  defp related_query(:callees, revision, entity) do
    {
      """
      SELECT target.entity_id, target.kind, target.current_semantic_key,
             r.relation_type, r.origin, r.confidence
      FROM semantic_relations r
      JOIN semantic_nodes target ON target.entity_id = r.target_node_id
      WHERE r.revision_id = ? AND r.source_node_id = ? AND r.relation_type = 'calls'
        AND r.origin IN ('source_derived', 'reconstructed')
      ORDER BY target.current_semantic_key
      """,
      [revision, entity]
    }
  end

  defp related_query(:derived_tests, revision, entity) do
    {
      """
      SELECT target.entity_id, target.kind, target.current_semantic_key,
             r.relation_type, r.origin, r.confidence
      FROM semantic_relations r
      JOIN semantic_nodes target ON target.entity_id = r.target_node_id
      WHERE r.revision_id = ? AND r.source_node_id = ? AND r.relation_type = 'tested_by'
        AND r.origin IN ('source_derived', 'reconstructed')
      ORDER BY target.current_semantic_key
      """,
      [revision, entity]
    }
  end

  defp related_query(:requested_tests, _revision, entity) do
    {
      """
      SELECT source.entity_id, source.kind, source.current_semantic_key,
             r.relation_type, r.origin, r.confidence
      FROM semantic_relations r
      JOIN semantic_nodes source ON source.entity_id = r.source_node_id
      WHERE r.target_node_id = ? AND r.relation_type = 'intended_to_test'
        AND r.origin = 'requested' AND source.lifecycle = 'active'
      ORDER BY source.current_semantic_key
      """,
      [entity]
    }
  end

  defp load_evidence(connection, revision_id, entity_id) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT evidence_type, status, origin, revision_id, reason, operation_id
             FROM semantic_evidence
             WHERE revision_id = ? AND subject_node_id = ?
             ORDER BY evidence_type, operation_id
             """,
             [revision_id, entity_id]
           ) do
      {:ok,
       Enum.map(rows, fn [type, status, origin, revision, reason, operation] ->
         %{
           type: type,
           status: status,
           origin: origin,
           revision: revision,
           reason: reason,
           operation: operation
         }
       end)}
    end
  end

  defp load_frontier(connection, revision_id) do
    with {:ok, rows} <-
           query(
             connection,
             """
             SELECT reason FROM semantic_evidence
             WHERE revision_id = ? AND evidence_type = 'unresolved_source' AND status = 'unknown'
             ORDER BY reason
             """,
             [revision_id]
           ) do
      {:ok, Enum.map(rows, &hd/1)}
    end
  end

  defp finish_transaction(connection, {:ok, value}) do
    case execute_static(connection, "COMMIT") do
      :ok ->
        {:ok, value}

      {:error, reason} ->
        _ = execute_static(connection, "ROLLBACK")
        {:error, reason}
    end
  end

  defp finish_transaction(connection, {:error, reason}) do
    case execute_static(connection, "ROLLBACK") do
      :ok ->
        {:error, reason}

      {:error, rollback} ->
        {:error, %{code: :semantic_store_rollback_failed, cause: reason, rollback: rollback}}
    end
  end

  defp finish_transaction(connection, other) do
    finish_transaction(
      connection,
      {:error, %{code: :invalid_transaction_result, value: inspect(other)}}
    )
  end

  defp execute_static(connection, sql) do
    case Sqlite3.execute(connection, sql) do
      :ok -> :ok
      {:error, reason} -> sqlite_error(reason)
    end
  end

  defp execute_bound(connection, sql, parameters) do
    with_statement(connection, sql, fn statement ->
      with :ok <- bind(statement, parameters) do
        execute_step(connection, statement)
      end
    end)
  end

  defp execute_step(connection, statement) do
    case Sqlite3.step(connection, statement) do
      :done -> :ok
      :busy -> {:error, %{code: :semantic_store_busy}}
      {:row, _row} -> {:error, %{code: :unexpected_semantic_store_row}}
      {:error, reason} -> sqlite_error(reason)
    end
  end

  defp query(connection, sql, parameters) do
    with_statement(connection, sql, fn statement ->
      with :ok <- bind(statement, parameters) do
        collect_rows(connection, statement, [])
      end
    end)
  end

  defp collect_rows(connection, statement, rows) do
    case Sqlite3.step(connection, statement) do
      {:row, row} -> collect_rows(connection, statement, [row | rows])
      :done -> {:ok, Enum.reverse(rows)}
      :busy -> {:error, %{code: :semantic_store_busy}}
      {:error, reason} -> sqlite_error(reason)
    end
  end

  defp with_statement(connection, sql, fun) do
    case Sqlite3.prepare(connection, sql) do
      {:ok, statement} ->
        result =
          try do
            fun.(statement)
          rescue
            error -> sqlite_error(error)
          end

        release_result = Sqlite3.release(connection, statement)
        combine_release(result, release_result)

      {:error, reason} ->
        sqlite_error(reason)
    end
  end

  defp bind(statement, parameters) do
    Sqlite3.bind(statement, parameters)
  rescue
    error -> sqlite_error(error)
  end

  defp combine_release(result, :ok), do: result
  defp combine_release({:error, reason}, {:error, _release}), do: {:error, reason}
  defp combine_release(_result, {:error, reason}), do: sqlite_error(reason)

  defp combine_close(result, :ok), do: result
  defp combine_close({:error, reason}, {:error, _close}), do: {:error, reason}
  defp combine_close(_result, {:error, reason}), do: sqlite_error(reason)

  defp sqlite_error(%{code: _code} = reason), do: {:error, reason}

  defp sqlite_error(reason) do
    diagnostic = reason |> inspect() |> String.downcase()

    code =
      cond do
        String.contains?(diagnostic, "constraint") ->
          :semantic_store_constraint

        String.contains?(diagnostic, "busy") or String.contains?(diagnostic, "locked") ->
          :semantic_store_busy

        true ->
          :semantic_store_error
      end

    {:error, %{code: code}}
  end

  defp dump_reason(nil), do: nil
  defp dump_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp load_reason(nil), do: nil
  defp load_reason("semantic_store_rebuilt_from_source"), do: :semantic_store_rebuilt_from_source
  defp load_reason(reason), do: reason
end
