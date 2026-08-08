defmodule TwoRavens.Change do
  @moduledoc "Entity-based, ordered, repairable Elixir authoring."

  alias TwoRavens.Change.Engine
  alias TwoRavens.Change.Error
  alias TwoRavens.Change.Receipt
  alias TwoRavens.Change.Request
  alias TwoRavens.Graph
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore

  @doc "Submits one strictly validated ordered entity-authoring request."
  @spec submit(Path.t(), map()) :: {:ok, Receipt.t()} | {:error, Error.t()}
  def submit(root, request) when is_binary(root) do
    with {:ok, validated} <- Request.validate(request),
         {:ok, project} <- Project.open(root),
         {:ok, _freshness} <- SemanticStore.synchronize(root),
         {:ok, receipt} <- Engine.run(project, validated) do
      {:ok, receipt}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.from(reason)}
    end
  end

  def submit(root, _request),
    do: {:error, Error.from(%{code: :invalid_arguments, reason: %{root: root}})}

  @doc "Returns compact semantic context for one entity in an uncommitted draft version."
  @spec draft_context(Path.t(), String.t(), pos_integer(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def draft_context(root, draft_id, version, focus)
      when is_binary(root) and is_binary(draft_id) and is_integer(version) and version > 0 and
             is_binary(focus) do
    with {:ok, project} <- Project.open(root),
         {:ok, draft} <- SemanticStore.get_draft(project, draft_id, version),
         {:ok, graph} <- TwoRavens.Source.rebuild_with(project, draft.manifest, draft.files),
         {:ok, entity} <- fetch_draft_entity(graph, focus) do
      {:ok,
       %{
         draft: draft.id,
         version: draft.version,
         status: draft.status,
         entity: entity,
         callers: Graph.callers(graph, focus),
         callees: Graph.callees(graph, focus),
         clauses: Map.get(entity, :clauses, []) |> Enum.map(& &1.id),
         diagnostics: draft.diagnostics
       }}
    else
      {:error, reason} -> {:error, Error.from(reason)}
    end
  end

  def draft_context(_root, _draft_id, _version, _focus),
    do: {:error, Error.from(%{code: :invalid_arguments})}

  defp fetch_draft_entity(graph, focus) do
    case Map.fetch(graph.nodes, focus) do
      {:ok, entity} -> {:ok, entity}
      :error -> {:error, %{code: :entity_not_found, target: focus}}
    end
  end
end
