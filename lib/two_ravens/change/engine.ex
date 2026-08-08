defmodule TwoRavens.Change.Engine do
  @moduledoc false

  alias TwoRavens.Authoring.CandidateBuilder
  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Authoring.Support
  alias TwoRavens.Change.Draft
  alias TwoRavens.Change.EntitySource
  alias TwoRavens.Change.Patch
  alias TwoRavens.Change.Projector
  alias TwoRavens.Change.Receipt
  alias TwoRavens.Change.SourceBundle
  alias TwoRavens.EditHandle
  alias TwoRavens.Graph
  alias TwoRavens.Identity
  alias TwoRavens.Manifest
  alias TwoRavens.Materializer
  alias TwoRavens.Project
  alias TwoRavens.Qualification.Evidence
  alias TwoRavens.Qualifier
  alias TwoRavens.Qualifier.Result
  alias TwoRavens.Selection
  alias TwoRavens.Semantic.Revision
  alias TwoRavens.SemanticStore
  alias TwoRavens.Source
  alias TwoRavens.Source.Clause
  alias TwoRavens.Source.Comparison
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Test

  @spec run(Project.t(), map()) :: {:ok, Receipt.t()} | {:error, map()}
  def run(%Project{} = project, request) do
    case replay(project, request) do
      {:ok, %Receipt{} = receipt} -> {:ok, receipt}
      {:ok, nil} -> run_new(project, request)
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_new(
         %Project{} = project,
         %{base: {:draft, _id, _version}, mode: :apply_if_valid, operations: []} = request
       ) do
    with {:ok, state} <- starting_state(project, request.base),
         :ok <- ready_to_apply(state.draft) do
      finish(project, state.draft, :apply_if_valid, request.returns, request)
    end
  end

  defp run_new(%Project{} = project, request) do
    with {:ok, state} <- starting_state(project, request.base),
         {:ok, transformed} <- apply_operations(state, request.operations),
         {:ok, projected} <- project_new_modules(transformed),
         {:ok, draft} <-
           persist_candidate(project, projected, request.operations, request.mode) do
      finish(project, draft, request.mode, request.returns, request)
    end
  end

  defp replay(_project, %{request_id: nil}), do: {:ok, nil}

  defp replay(project, %{request_id: request_id, request_hash: request_hash}) do
    SemanticStore.accepted_request(project, request_id, request_hash)
  end

  defp ready_to_apply(%Draft{status: :ready}), do: :ok

  defp ready_to_apply(%Draft{id: id, version: version, status: status}) do
    {:error, %{code: :draft_not_ready, draft: id, version: version, status: status}}
  end

  defp starting_state(project, {:revision, expected}) do
    with {:ok, manifest} <- Manifest.load(project),
         {:ok, manifest_hash} <- Manifest.content_hash(project),
         {:ok, graph} <- Source.rebuild(project, manifest),
         :ok <- verify_revision(graph, expected),
         {:ok, files} <- load_files(project, manifest) do
      {:ok, base_state(project, manifest, manifest_hash, graph, files)}
    end
  end

  defp starting_state(project, :empty_project) do
    with {:ok, manifest} <- Manifest.load(project),
         true <- manifest.managed_paths == [],
         {:ok, manifest_hash} <- Manifest.content_hash(project),
         {:ok, graph} <- Source.rebuild(project, manifest) do
      {:ok, base_state(project, manifest, manifest_hash, graph, %{})}
    else
      false -> {:error, %{code: :base_revision_required}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp starting_state(project, {:draft, id, version}) do
    with {:ok, draft} <- SemanticStore.get_draft(project, id, version),
         {:ok, current_manifest} <- Manifest.load(project),
         {:ok, current_graph} <- Source.rebuild(project, current_manifest),
         true <- current_graph.revision.working_hash == draft.base_working_hash,
         {:ok, graph} <- Source.rebuild_with(project, draft.manifest, draft.files) do
      {:ok,
       %{
         project: project,
         manifest: draft.manifest,
         manifest_hash: draft.manifest_hash,
         graph: graph,
         files: draft.files,
         before_files: draft.before_files,
         base_hashes: draft.base_hashes,
         base_working_hash: draft.base_working_hash,
         base_revision: draft.base_revision,
         draft: draft,
         new_paths:
           draft.files
           |> Map.keys()
           |> Enum.reject(&Map.has_key?(draft.before_files, &1))
           |> MapSet.new(),
         counts: %{}
       }}
    else
      false -> {:error, %{code: :stale_draft_base, draft: id, version: version}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_state(project, manifest, manifest_hash, graph, files) do
    %{
      project: project,
      manifest: manifest,
      manifest_hash: manifest_hash,
      graph: graph,
      files: files,
      before_files: files,
      base_hashes: graph.revision.file_hashes,
      base_working_hash: graph.revision.working_hash,
      base_revision: revision_id(graph),
      draft: nil,
      new_paths: MapSet.new(),
      counts: %{}
    }
  end

  defp apply_operations(state, operations) do
    operations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state}, fn {operation, index}, {:ok, current} ->
      case apply_and_rebuild(current, operation) do
        {:ok, rebuilt} ->
          {:cont, {:ok, count(rebuilt, operation)}}

        {:error, reason} ->
          {:halt, {:error, annotate(reason, index, operation)}}
      end
    end)
  end

  defp apply_and_rebuild(state, operation) do
    with {:ok, changed} <- apply_operation(state, operation), do: rebuild(changed)
  end

  defp apply_operation(state, %{"op" => "create", "kind" => "source_bundle"} = operation) do
    with {:ok, modules} <- SourceBundle.split(operation["text"]),
         :ok <- reject_module_collisions(state, modules),
         {:ok, manifest} <- add_paths(state.manifest, modules) do
      files = Enum.reduce(modules, state.files, &Map.put(&2, &1.path, &1.source))
      new_paths = Enum.reduce(modules, state.new_paths, &MapSet.put(&2, &1.path))

      base_hashes =
        Enum.reduce(modules, state.base_hashes, &Map.put_new(&2, &1.path, nil))

      {:ok,
       %{
         state
         | files: files,
           manifest: manifest,
           new_paths: new_paths,
           base_hashes: base_hashes
       }}
    end
  end

  defp apply_operation(state, %{"op" => "create", "kind" => "function"} = operation) do
    with {:ok, parent} <- EntitySource.locate(state.graph, state.files, operation["parent"]),
         :module <- parent.kind,
         {:ok, function} <- EntitySource.validate_function(operation["text"]),
         id <- Identity.function(parent.module, function.name, function.arity),
         false <- Map.has_key?(state.graph.nodes, id),
         {:ok, files} <- EntitySource.append_to_module(state.files, parent, operation["text"]) do
      {:ok, %{state | files: files}}
    else
      true -> {:error, %{code: :entity_collision}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, %{code: :invalid_parent, expected: :module}}
    end
  end

  defp apply_operation(state, %{"op" => "create", "kind" => "clause"} = operation) do
    with %Function{} = function <- Map.get(state.graph.nodes, operation["parent"]),
         {:ok, clause} <- EntitySource.validate_clause(operation["text"], function),
         {:ok, side, anchor_id} <- anchor(operation),
         true <- Enum.any?(function.clauses, &(&1.id == anchor_id)),
         {:ok, anchor_entity} <- EntitySource.locate(state.graph, state.files, anchor_id),
         {:ok, files} <- EntitySource.insert_clause(state.files, anchor_entity, clause, side) do
      {:ok, %{state | files: files}}
    else
      nil -> {:error, %{code: :entity_not_found, target: operation["parent"]}}
      false -> {:error, %{code: :anchor_outside_parent, anchor: anchor_value(operation)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_operation(state, %{"op" => "create", "kind" => "module_form"} = operation) do
    with :ok <- one_form(operation["text"]),
         {:ok, parent} <- EntitySource.locate(state.graph, state.files, operation["parent"]),
         :module <- parent.kind,
         {:ok, files} <- EntitySource.append_to_module(state.files, parent, operation["text"]) do
      {:ok, %{state | files: files}}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, %{code: :invalid_parent, expected: :module}}
    end
  end

  defp apply_operation(_state, %{"op" => "create", "kind" => kind}),
    do: {:error, %{code: :unsupported_entity_kind, kind: kind}}

  defp apply_operation(state, %{"op" => "replace"} = operation) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, operation["target"]),
         :ok <- replace_allowed(entity, operation["text"], state.graph),
         {:ok, files} <- EntitySource.replace_fragment(state.files, entity, operation["text"]) do
      {:ok, %{state | files: files}}
    end
  end

  defp apply_operation(state, %{"op" => "patch"} = operation) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, operation["target"]),
         :ok <- patch_allowed(entity),
         {:ok, fragment} <- Patch.apply(entity.source, operation["diff"], operation["hash"]),
         :ok <- validate_patched_entity(entity, fragment),
         {:ok, files} <- EntitySource.replace_fragment(state.files, entity, fragment) do
      {:ok, %{state | files: files}}
    end
  end

  defp apply_operation(state, %{"op" => "set", "handle" => handle, "value" => value}) do
    set_handle(state, handle, value)
  end

  defp apply_operation(state, %{"op" => "set", "field" => "doc"} = operation) do
    with {:ok, module_entity} <-
           EntitySource.locate(state.graph, state.files, operation["target"]),
         :module <- module_entity.kind,
         true <- is_binary(operation["value"]),
         {:ok, changed} <- set_module_doc(module_entity.source, operation["value"]),
         {:ok, formatted} <- Support.format(changed, module_entity.path) do
      {:ok, %{state | files: Map.put(state.files, module_entity.path, formatted)}}
    else
      false -> {:error, %{code: :invalid_set_value, expected: :string}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, %{code: :invalid_set_target}}
    end
  end

  defp apply_operation(_state, %{"op" => "set"}),
    do: {:error, %{code: :unsupported_set_property}}

  defp apply_operation(state, %{"op" => "delete"} = operation) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, operation["target"]) do
      delete_entity(state, entity, operation)
    end
  end

  defp apply_operation(state, %{"op" => "rename"} = operation) do
    rename_entity(state, operation["target"], operation["to"])
  end

  defp apply_operation(state, %{"op" => "move"} = operation) do
    move_entity(state, operation)
  end

  defp patch_allowed(%{kind: :module}),
    do: {:error, %{code: :whole_module_patch_not_allowed}}

  defp patch_allowed(%{kind: kind}) when kind in [:function, :clause, :module_form, :test],
    do: :ok

  defp validate_patched_entity(%{kind: :test}, fragment) do
    case EntitySource.validate_test(fragment) do
      {:ok, %Test{}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_patched_entity(_entity, _fragment), do: :ok

  defp rebuild(state) do
    with {:ok, graph} <- Source.rebuild_with(state.project, state.manifest, state.files) do
      {:ok, %{state | graph: graph}}
    end
  end

  defp project_new_modules(state) do
    with {:ok, files} <- Projector.order_new_modules(state.graph, state.files, state.new_paths),
         {:ok, graph} <- Source.rebuild_with(state.project, state.manifest, files) do
      {:ok, %{state | files: files, graph: graph}}
    end
  end

  defp persist_candidate(project, state, operations, mode) do
    draft =
      draft_value(state, operations, :ready, [], nil)

    with {:ok, qualified} <- qualify(state, mode),
         ready <- update_qualified_draft(draft, state, qualified),
         {:ok, persisted} <- SemanticStore.put_draft(project, ready) do
      {:ok, persisted}
    else
      {:error, reason} ->
        failed = draft_value(state, operations, :needs_changes, [reason], nil)
        SemanticStore.put_draft(project, failed)
    end
  end

  defp qualify(state, mode) do
    changed = changed_files(state.before_files, state.files)
    profile = if mode == :apply_if_valid, do: :apply, else: :qualified_dry_run
    Qualifier.qualify(state.project, state.manifest, changed, state.graph, profile)
  end

  defp finish(project, %Draft{status: :needs_changes} = draft, _mode, selectors, _request) do
    with {:ok, selected} <- select(project, draft, selectors) do
      {:ok, receipt(draft, :needs_changes, false, nil, selected)}
    end
  end

  defp finish(project, %Draft{} = draft, :draft_only, selectors, _request) do
    with {:ok, selected} <- select(project, draft, selectors) do
      {:ok, receipt(draft, :ready, false, nil, selected)}
    end
  end

  defp finish(project, %Draft{} = draft, :apply_if_valid, selectors, request) do
    with {:ok, graph} <- Source.rebuild_with(project, draft.manifest, draft.files),
         {:ok, selected} <- Selection.resolve(graph, draft.files, selectors),
         revision <- revision_id(graph),
         applied_receipt <- receipt(draft, :applied, true, revision, selected),
         accepted_request <- accepted_request(request, applied_receipt),
         {:ok, candidate} <- candidate(project, draft, graph, accepted_request),
         {:ok, _applied} <- apply_candidate(candidate) do
      {:ok, clean_up_draft(project, draft.id, applied_receipt)}
    end
  end

  defp apply_candidate(candidate) do
    case Materializer.apply(candidate) do
      {:error, %{code: :apply_failed} = error} ->
        {:error, Map.put(error, :working_tree_changed, false)}

      result ->
        result
    end
  end

  defp accepted_request(%{request_id: nil}, _receipt), do: nil

  defp accepted_request(request, receipt) do
    %{id: request.request_id, hash: request.request_hash, receipt: receipt}
  end

  defp select(_project, _draft, []), do: {:ok, []}

  defp select(project, draft, selectors) do
    with {:ok, graph} <- Source.rebuild_with(project, draft.manifest, draft.files) do
      Selection.resolve(graph, draft.files, selectors)
    end
  end

  defp clean_up_draft(project, draft_id, receipt) do
    case SemanticStore.delete_draft(project, draft_id) do
      :ok ->
        receipt

      {:error, reason} ->
        warning = %{code: :draft_cleanup_failed, reason: reason}
        %{receipt | diagnostics: receipt.diagnostics ++ [warning]}
    end
  end

  defp candidate(project, draft, graph, accepted_request) do
    changed = changed_files(draft.before_files, draft.files)

    case graph.nodes |> Map.keys() |> Enum.sort() |> List.first() do
      nil ->
        {:error, %{code: :empty_candidate_graph}}

      subject ->
        proposal = %Proposal{
          kind: :set,
          project: project,
          files: changed,
          before_files: Map.take(draft.before_files, Map.keys(changed)),
          base_hashes: draft.base_hashes,
          base_working_hash: draft.base_working_hash,
          manifest: draft.manifest,
          manifest_hash: draft.manifest_hash,
          graph: graph,
          details: %{
            operation_count: length(draft.operations),
            accepted_request: accepted_request
          },
          semantic: %{subject: subject, intent: nil, intent_kind: :change_reason, targets: []}
        }

        evidence = Evidence.applied(0, 2)
        {:ok, CandidateBuilder.build(proposal, evidence)}
    end
  end

  defp draft_value(state, operations, status, diagnostics, qualification) do
    attributes = %{
      base_revision: state.base_revision,
      base_working_hash: state.base_working_hash,
      base_hashes: state.base_hashes,
      manifest_hash: state.manifest_hash,
      manifest: state.manifest,
      files: state.files,
      before_files: state.before_files,
      operations: operations,
      status: status,
      diagnostics: diagnostics,
      qualification: qualification
    }

    case state.draft do
      nil -> Draft.new(attributes)
      draft -> Draft.next(draft, attributes)
    end
  end

  defp update_qualified_draft(draft, state, %Result{} = result) do
    files = Map.merge(state.files, result.files)

    %{
      draft
      | files: files,
        qualification: qualification_summary(result),
        status: :ready,
        diagnostics: []
    }
  end

  defp qualification_summary(%Result{evidence: evidence}) do
    %{
      format: evidence.format,
      compile: evidence.compile,
      tests: evidence.tests,
      commands: evidence.commands,
      output_bytes: evidence.output_bytes
    }
  end

  defp receipt(draft, status, changed?, revision, selected) do
    %Receipt{
      status: status,
      operation_count: length(draft.operations),
      draft: if(status == :applied, do: nil, else: draft.id),
      draft_version: if(status == :applied, do: nil, else: draft.version),
      revision: revision,
      entities: entity_counts(draft.operations),
      relationships: %{},
      qualification: draft.qualification,
      affected_paths: map_size(changed_files(draft.before_files, draft.files)),
      diagnostics: draft.diagnostics,
      selected: selected,
      selected_from: selected_from(draft, status, revision),
      working_tree_changed: changed?
    }
  end

  defp selected_from(_draft, :applied, revision), do: %{revision: revision}

  defp selected_from(draft, _status, _revision) do
    %{draft: draft.id, draft_version: draft.version}
  end

  defp entity_counts(operations) do
    operations
    |> Enum.group_by(& &1["op"])
    |> Map.new(fn {operation, grouped} ->
      {operation_atom(operation), length(grouped)}
    end)
  end

  defp changed_files(before, current) do
    (Map.keys(before) ++ Map.keys(current))
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn path, changed ->
      previous = Map.get(before, path, :missing)
      candidate = Map.get(current, path, nil)

      if previous == candidate, do: changed, else: Map.put(changed, path, candidate)
    end)
  end

  defp load_files(project, manifest) do
    Enum.reduce_while(manifest.managed_paths, {:ok, %{}}, fn path, {:ok, files} ->
      case Support.read_source(project, path) do
        {:ok, source} -> {:cont, {:ok, Map.put(files, path, source)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reject_module_collisions(state, modules) do
    collision =
      Enum.find(modules, fn module ->
        Map.has_key?(state.graph.nodes, Identity.module(module.module)) or
          candidate_path_collision?(state, module.path) or
          unmanaged_path_exists?(state.project, module.path)
      end)

    if collision,
      do: {:error, %{code: :module_collision, module: collision.module}},
      else: :ok
  end

  defp candidate_path_collision?(state, path) do
    case Map.fetch(state.files, path) do
      {:ok, nil} -> not MapSet.member?(state.new_paths, path)
      {:ok, _source} -> true
      :error -> false
    end
  end

  defp unmanaged_path_exists?(project, path) do
    with {:ok, absolute} <- Project.resolve(project, path), do: File.exists?(absolute)
  end

  defp add_paths(manifest, modules) do
    Enum.reduce_while(modules, {:ok, manifest}, fn module, {:ok, current} ->
      case Manifest.add(current, module.path) do
        {:ok, changed} -> {:cont, {:ok, changed}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp replace_allowed(%{kind: :module}, _text, _graph),
    do: {:error, %{code: :whole_module_replace_not_allowed}}

  defp replace_allowed(%{kind: :function, id: id}, text, _graph) do
    with {:ok, replacement} <- EntitySource.validate_function(text),
         {:ok, expected} <- parse_function_id(id),
         true <- {replacement.name, replacement.arity} == expected do
      :ok
    else
      false -> {:error, %{code: :replacement_identity_mismatch, target: id}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_allowed(%{kind: :clause, id: id}, text, graph) do
    %Clause{function_id: function_id} = Map.fetch!(graph.nodes, id)
    %Function{} = function = Map.fetch!(graph.nodes, function_id)

    case EntitySource.validate_clause(text, function) do
      {:ok, _clause} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp replace_allowed(%{kind: :module_form}, text, _graph), do: one_form(text)

  defp replace_allowed(%{kind: :test, id: id, name: name}, text, _graph) do
    case EntitySource.validate_test(text, name) do
      {:ok, %Test{}} ->
        :ok

      {:error, %{code: :replacement_identity_mismatch} = reason} ->
        {:error, Map.put(reason, :target, id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_function_id(id) do
    case Regex.run(~r/^function:.+\.([a-z_][A-Za-z0-9_!?]*)\/(\d+)$/, id) do
      [_whole, name, arity] -> {:ok, {name, String.to_integer(arity)}}
      _other -> {:error, %{code: :invalid_function_identity, target: id}}
    end
  end

  defp anchor(%{"before" => id}), do: {:ok, :before, id}
  defp anchor(%{"after" => id}), do: {:ok, :after, id}
  defp anchor(_operation), do: {:error, %{code: :ambiguous_clause_placement}}

  defp anchor_value(operation), do: operation["before"] || operation["after"]

  defp one_form(text) do
    wrapper = "defmodule TwoRavens.Form do\n#{Support.indent(text)}\nend"

    with {:ok, source} <- Support.format(wrapper, "module_form.ex"),
         {:ok, fragment} <- Source.parse("module_form.ex", source) do
      case {fragment.functions, fragment.tests, fragment.module_forms,
            fragment.module.documentation} do
        {[], [], [_one], nil} -> :ok
        _other -> {:error, %{code: :one_module_form_required}}
      end
    end
  end

  defp set_handle(state, handle_string, value) do
    with {:ok, handle} <- EditHandle.decode(String.replace_suffix(handle_string, ".operator", "")),
         true <- handle.property == "operator",
         true <- value in ["==", "!=", "===", "!==", "<", "<=", ">", ">="],
         %Comparison{} = comparison <- resolve_comparison(state.graph, handle),
         {:ok, changed} <- replace_comparison(state.files[handle.path], comparison, value) do
      {:ok, %{state | files: Map.put(state.files, handle.path, changed)}}
    else
      false -> {:error, %{code: :unsupported_set_value, value: value}}
      nil -> {:error, %{code: :stale_handle}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_comparison(graph, handle) do
    graph.nodes
    |> Map.values()
    |> Enum.find(fn
      %Comparison{} = comparison ->
        comparison.source.path == handle.path and
          comparison.function_id == handle.function_id and
          comparison.clause_fingerprint == handle.clause_fingerprint and
          comparison.fingerprint == handle.expression_fingerprint

      _other ->
        false
    end)
  end

  defp replace_comparison(source, comparison, value) do
    lines = String.split(source, "\n", trim: false)
    index = comparison.source.start_line - 1
    column = comparison.source.start_column - 1
    line = Enum.at(lines, index)

    if line &&
         String.slice(line, column, String.length(comparison.operator)) == comparison.operator do
      changed =
        String.slice(line, 0, column) <>
          value <>
          String.slice(line, (column + String.length(comparison.operator))..-1//1)

      {:ok, lines |> List.replace_at(index, changed) |> Enum.join("\n")}
    else
      {:error, %{code: :stale_handle}}
    end
  end

  defp set_module_doc(source, value) do
    replacement = "@moduledoc " <> inspect(value)
    pattern = ~r/@moduledoc\s+(?:""".*?"""|"(?:\\.|[^"])*"|false)/s

    case Regex.scan(pattern, source) do
      [_one] -> {:ok, Regex.replace(pattern, source, replacement, global: false)}
      [] -> {:error, %{code: :module_document_not_found}}
      _many -> {:error, %{code: :ambiguous_module_document}}
    end
  end

  defp delete_entity(state, %{kind: kind} = entity, _operation)
       when kind in [:function, :clause, :module_form, :test] do
    with {:ok, files} <- EntitySource.delete_fragment(state.files, entity) do
      {:ok, %{state | files: files}}
    end
  end

  defp delete_entity(state, %{kind: :module, path: path, id: id}, %{"cascade" => true}) do
    children = Enum.filter(state.graph.edges, &(&1.kind == :defines and &1.from == id))

    with {:ok, manifest} <- remove_manifest_path(state.manifest, path) do
      {:ok,
       %{
         state
         | manifest: manifest,
           files: Map.put(state.files, path, nil),
           counts: Map.put(state.counts, :cascade_children, length(children))
       }}
    end
  end

  defp delete_entity(_state, %{kind: :module, id: id}, _operation),
    do: {:error, %{code: :module_cascade_required, target: id}}

  defp remove_manifest_path(manifest, path) do
    {:ok, %{manifest | managed_paths: List.delete(manifest.managed_paths, path)}}
  end

  defp rename_entity(state, "function:" <> _ = target, "function:" <> _ = destination) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, target),
         [] <- Graph.callers(state.graph, target),
         {:ok, {_old_name, arity}} <- parse_function_id(target),
         {:ok, {new_name, ^arity}} <- parse_function_id(destination),
         true <- destination_module(destination) == entity.module,
         false <- Map.has_key?(state.graph.nodes, destination),
         changed <- rename_function_definitions(entity.source, new_name),
         {:ok, files} <- EntitySource.replace_fragment(state.files, entity, changed) do
      {:ok, %{state | files: files}}
    else
      [_caller | _rest] -> {:error, %{code: :unresolved_references, target: target}}
      true -> {:error, %{code: :entity_collision, target: destination}}
      false -> {:error, %{code: :rename_changes_parent_or_arity}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rename_entity(state, "module:" <> old, "module:" <> new) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, "module:" <> old),
         :ok <- Project.validate_module_name(new),
         false <- Map.has_key?(state.graph.nodes, "module:" <> new),
         false <- external_module_reference?(state.files, entity.path, old),
         changed <-
           String.replace(entity.source, "defmodule #{old}", "defmodule #{new}", global: false) do
      {:ok, %{state | files: Map.put(state.files, entity.path, changed)}}
    else
      true -> {:error, %{code: :unresolved_references, target: "module:" <> old}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rename_entity(_state, target, destination),
    do: {:error, %{code: :unsupported_rename, target: target, to: destination}}

  defp move_entity(state, %{"target" => "clause:" <> _ = target} = operation) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, target),
         {:ok, side, anchor_id} <- anchor(operation),
         {:ok, _anchor_entity} <- EntitySource.locate(state.graph, state.files, anchor_id),
         true <- clause_parent(state.graph, target) == clause_parent(state.graph, anchor_id),
         {:ok, without} <- EntitySource.delete_fragment(state.files, entity),
         {:ok, intermediate} <- Source.rebuild_with(state.project, state.manifest, without),
         {:ok, moved_anchor} <- EntitySource.locate(intermediate, without, anchor_id),
         {:ok, files} <-
           EntitySource.insert_clause(without, moved_anchor, %{text: entity.source}, side) do
      {:ok, %{state | files: files}}
    else
      false -> {:error, %{code: :anchor_outside_parent}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp move_entity(state, %{"target" => "function:" <> _ = target, "to" => "module:" <> _ = to}) do
    with {:ok, entity} <- EntitySource.locate(state.graph, state.files, target),
         [] <- Graph.callers(state.graph, target),
         {:ok, destination} <- EntitySource.locate(state.graph, state.files, to),
         :module <- destination.kind,
         false <- function_collision_in_module?(state.graph, entity, destination.module),
         {:ok, removed} <- EntitySource.delete_fragment(state.files, entity),
         {:ok, files} <- EntitySource.append_to_module(removed, destination, entity.source) do
      {:ok, %{state | files: files}}
    else
      [_caller | _rest] -> {:error, %{code: :unresolved_references, target: target}}
      true -> {:error, %{code: :entity_collision}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, %{code: :invalid_move_destination}}
    end
  end

  defp move_entity(_state, operation),
    do: {:error, %{code: :unsupported_move, target: operation["target"]}}

  defp rename_function_definitions(source, new_name) do
    Regex.replace(
      ~r/\b(defp?)\s+[a-z_][A-Za-z0-9_!?]*(?=\s*(?:\(|,|when\b|do\b))/,
      source,
      "\\1 #{new_name}"
    )
  end

  defp destination_module(destination) do
    [module_and_name, _arity] =
      destination |> String.replace_prefix("function:", "") |> String.split("/")

    module_and_name |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")
  end

  defp external_module_reference?(files, own_path, module) do
    files
    |> Enum.reject(fn {path, _source} -> path == own_path end)
    |> Enum.any?(fn {_path, source} -> String.contains?(source, module) end)
  end

  defp clause_parent(graph, id) do
    case Map.get(graph.nodes, id) do
      %Clause{function_id: parent} -> parent
      _other -> nil
    end
  end

  defp function_collision_in_module?(graph, entity, module) do
    {:ok, {name, arity}} = parse_function_id(entity.id)
    Map.has_key?(graph.nodes, Identity.function(module, name, arity))
  end

  defp count(state, operation) do
    key = operation_atom(operation["op"])
    %{state | counts: Map.update(state.counts, key, 1, &(&1 + 1))}
  end

  defp annotate(reason, index, operation) do
    reason
    |> Map.put_new(:operation, index)
    |> Map.put_new(:target, operation["target"] || operation["parent"])
  end

  defp verify_revision(graph, expected) do
    if expected in [revision_id(graph), graph.revision.working_hash],
      do: :ok,
      else:
        {:error, %{code: :stale_base_revision, expected: expected, current: revision_id(graph)}}
  end

  defp revision_id(graph), do: Revision.from_repository(graph.revision, :available).id

  defp operation_atom("create"), do: :create
  defp operation_atom("replace"), do: :replace
  defp operation_atom("patch"), do: :patch
  defp operation_atom("set"), do: :set
  defp operation_atom("delete"), do: :delete
  defp operation_atom("rename"), do: :rename
  defp operation_atom("move"), do: :move
end
