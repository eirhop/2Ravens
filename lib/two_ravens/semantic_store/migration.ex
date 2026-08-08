defmodule TwoRavens.SemanticStore.Migration do
  @moduledoc "Forward-only schema migrations for local semantic memory."

  @current_version 4

  @doc "Returns the current supported schema version."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc false
  @spec statements(pos_integer()) :: [String.t()]
  def statements(1) do
    [
      """
      CREATE TABLE semantic_revisions (
        id TEXT PRIMARY KEY,
        working_hash TEXT NOT NULL UNIQUE,
        git_revision TEXT,
        created_at TEXT NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1)),
        intent_status TEXT NOT NULL CHECK (intent_status IN ('available', 'unavailable')),
        reconstruction_reason TEXT
      ) STRICT
      """,
      """
      CREATE UNIQUE INDEX semantic_revisions_one_current
      ON semantic_revisions(is_current) WHERE is_current = 1
      """,
      """
      CREATE TABLE semantic_nodes (
        entity_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        current_semantic_key TEXT NOT NULL,
        lifecycle TEXT NOT NULL CHECK (lifecycle IN ('active', 'retired', 'unresolved')),
        origin TEXT NOT NULL CHECK (origin IN (
          'requested', 'source_derived', 'compiler_confirmed',
          'test_observed', 'runtime_observed', 'reconstructed'
        )),
        fingerprint TEXT NOT NULL,
        created_revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        updated_revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        UNIQUE (updated_revision_id, current_semantic_key)
      ) STRICT
      """,
      """
      CREATE INDEX semantic_nodes_current_key
      ON semantic_nodes(updated_revision_id, current_semantic_key, lifecycle)
      """,
      """
      CREATE INDEX semantic_nodes_reconcile
      ON semantic_nodes(kind, fingerprint, lifecycle)
      """,
      """
      CREATE TABLE source_projections (
        id INTEGER PRIMARY KEY,
        node_id TEXT NOT NULL REFERENCES semantic_nodes(entity_id),
        revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        managed_path TEXT NOT NULL,
        start_line INTEGER NOT NULL CHECK (start_line > 0),
        start_column INTEGER NOT NULL CHECK (start_column > 0),
        end_line INTEGER NOT NULL CHECK (end_line > 0),
        end_column INTEGER NOT NULL CHECK (end_column > 0),
        content_hash TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        origin TEXT NOT NULL CHECK (origin IN ('source_derived', 'reconstructed')),
        UNIQUE (node_id, revision_id)
      ) STRICT
      """,
      """
      CREATE INDEX source_projections_revision_path
      ON source_projections(revision_id, managed_path)
      """,
      """
      CREATE TABLE semantic_relations (
        id INTEGER PRIMARY KEY,
        source_node_id TEXT NOT NULL REFERENCES semantic_nodes(entity_id),
        relation_type TEXT NOT NULL CHECK (relation_type IN (
          'defines', 'calls', 'tested_by', 'intended_to_test'
        )),
        target_node_id TEXT NOT NULL REFERENCES semantic_nodes(entity_id),
        origin TEXT NOT NULL CHECK (origin IN (
          'requested', 'source_derived', 'compiler_confirmed',
          'test_observed', 'runtime_observed', 'reconstructed'
        )),
        confidence TEXT NOT NULL CHECK (confidence IN (
          'asserted', 'derived', 'confirmed', 'unknown'
        )),
        revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        source_path TEXT NOT NULL DEFAULT '',
        start_line INTEGER NOT NULL DEFAULT 0,
        start_column INTEGER NOT NULL DEFAULT 0,
        identity_key TEXT NOT NULL UNIQUE
      ) STRICT
      """,
      """
      CREATE INDEX semantic_relations_target
      ON semantic_relations(revision_id, target_node_id, relation_type)
      """,
      """
      CREATE INDEX semantic_relations_source
      ON semantic_relations(revision_id, source_node_id, relation_type)
      """,
      """
      CREATE TABLE semantic_operations (
        operation_id TEXT PRIMARY KEY,
        requested_action TEXT NOT NULL CHECK (requested_action IN (
          'create_module', 'create_function', 'set'
        )),
        base_revision_id TEXT REFERENCES semantic_revisions(id),
        result_revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        result TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('accepted')),
        created_at TEXT NOT NULL
      ) STRICT
      """,
      """
      CREATE TABLE semantic_intents (
        id INTEGER PRIMARY KEY,
        subject_node_id TEXT NOT NULL REFERENCES semantic_nodes(entity_id),
        intent_text TEXT NOT NULL CHECK (length(intent_text) BETWEEN 1 AND 1000),
        intent_kind TEXT NOT NULL CHECK (intent_kind IN ('purpose', 'change_reason')),
        operation_id TEXT NOT NULL REFERENCES semantic_operations(operation_id),
        revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        origin TEXT NOT NULL CHECK (origin = 'requested'),
        UNIQUE (subject_node_id, intent_text, intent_kind, operation_id)
      ) STRICT
      """,
      """
      CREATE INDEX semantic_intents_subject
      ON semantic_intents(subject_node_id, revision_id)
      """,
      """
      CREATE TABLE semantic_evidence (
        id INTEGER PRIMARY KEY,
        subject_node_id TEXT REFERENCES semantic_nodes(entity_id),
        operation_id TEXT REFERENCES semantic_operations(operation_id),
        evidence_type TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('pass', 'fail', 'unknown', 'not_run')),
        origin TEXT NOT NULL CHECK (origin IN (
          'requested', 'source_derived', 'compiler_confirmed',
          'test_observed', 'runtime_observed', 'reconstructed'
        )),
        revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        reason TEXT,
        identity_key TEXT NOT NULL UNIQUE
      ) STRICT
      """,
      """
      CREATE INDEX semantic_evidence_subject
      ON semantic_evidence(revision_id, subject_node_id, evidence_type)
      """
    ]
  end

  def statements(2) do
    [
      """
      CREATE TABLE change_drafts (
        draft_id TEXT NOT NULL,
        version INTEGER NOT NULL CHECK (version > 0),
        base_revision TEXT NOT NULL,
        base_working_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('ready', 'needs_changes')),
        expires_at TEXT NOT NULL,
        payload BLOB NOT NULL CHECK (length(payload) <= 5000000),
        payload_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (draft_id, version)
      ) STRICT
      """,
      """
      CREATE INDEX change_drafts_expiry ON change_drafts(expires_at)
      """
    ]
  end

  def statements(3) do
    [
      """
      CREATE TABLE accepted_change_requests (
        request_id TEXT PRIMARY KEY,
        request_hash TEXT NOT NULL,
        result_revision_id TEXT NOT NULL REFERENCES semantic_revisions(id),
        receipt BLOB NOT NULL CHECK (length(receipt) <= 1000000),
        receipt_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      ) STRICT
      """
    ]
  end

  def statements(4) do
    [
      """
      CREATE TABLE change_request_attempts (
        attempt_id TEXT NOT NULL,
        version INTEGER NOT NULL CHECK (version > 0),
        expires_at TEXT NOT NULL,
        payload BLOB NOT NULL CHECK (length(payload) <= 1200000),
        payload_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (attempt_id, version)
      ) STRICT
      """,
      """
      CREATE INDEX change_request_attempts_expiry ON change_request_attempts(expires_at)
      """
    ]
  end
end
