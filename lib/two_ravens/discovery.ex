defmodule TwoRavens.Discovery do
  @moduledoc """
  Finds canonical modules and functions in the current managed-source graph.

  Discovery is local and deterministic. Returned paths are source evidence for
  orientation only; they are not write capabilities.
  """

  alias TwoRavens.Graph
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.SemanticStore
  alias TwoRavens.Source
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Module

  @default_limit 10
  @max_limit 20
  @max_query_chars 200
  @max_doc_chars 240
  @max_module_functions 20
  @allowed_keys ~w(query limit kinds)
  @allowed_kinds ~w(module function)

  @typedoc "A flat, bounded discovery request."
  @type request :: %{String.t() => String.t() | pos_integer() | [String.t()]}

  @doc """
  Searches one freshness-checked managed-source revision.

  `query` may be a canonical focus, module/function suffix, name prefix,
  documentation terms, or `*` for a bounded namespace listing. `kinds` accepts
  `"module"` and `"function"`. A wildcard request without `kinds` lists
  modules, whose summaries already contain their public functions.
  """
  @spec query(Path.t(), request()) :: {:ok, map()} | {:error, map()}
  def query(root, request) when is_binary(root) and is_map(request) do
    with {:ok, request} <- validate_request(request),
         {:ok, freshness} <- SemanticStore.synchronize(root),
         {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         {:ok, graph} <- Source.rebuild(project, manifest),
         :ok <- ensure_same_revision(graph, freshness.revision.working_hash) do
      {:ok, discover(graph, freshness.revision.id, request)}
    end
  end

  def query(root, request),
    do: {:error, %{code: :invalid_arguments, arguments: %{root: root, request: request}}}

  @doc false
  @spec focus_suggestions(Graph.t(), String.t(), pos_integer()) :: [String.t()]
  def focus_suggestions(%Graph{} = graph, focus, limit)
      when is_binary(focus) and is_integer(limit) and limit > 0 do
    prefix = focus_kind_prefix(focus)
    wanted = focus |> strip_focus() |> local_name() |> normalize()

    graph.nodes
    |> Map.keys()
    |> Enum.filter(&(String.starts_with?(&1, prefix) and suggestion_local_name(&1) == wanted))
    |> Enum.sort()
    |> Enum.take(limit)
  end

  def focus_suggestions(_graph, _focus, _limit), do: []

  defp validate_request(request) do
    unknown = request |> Map.keys() |> Enum.reject(&(&1 in @allowed_keys)) |> Enum.sort()

    with :ok <- ensure_no_unknown_fields(unknown),
         {:ok, query} <- validate_query(Map.get(request, "query")),
         {:ok, limit, warning} <- validate_limit(Map.get(request, "limit", @default_limit)),
         {:ok, kinds} <- validate_kinds(Map.get(request, "kinds"), query) do
      {:ok, %{query: query, limit: limit, kinds: kinds, warning: warning}}
    end
  end

  defp ensure_no_unknown_fields([]), do: :ok

  defp ensure_no_unknown_fields(fields) do
    {:error,
     %{
       code: :invalid_discovery_request,
       reason: :unknown_fields,
       fields: fields,
       allowed_fields: @allowed_keys
     }}
  end

  defp validate_query(query) when is_binary(query) do
    if String.valid?(query) do
      query = String.trim(query)

      cond do
        query == "" ->
          {:error, %{code: :invalid_discovery_query, reason: :required}}

        String.length(query) > @max_query_chars ->
          {:error,
           %{code: :invalid_discovery_query, reason: :too_long, max_chars: @max_query_chars}}

        true ->
          {:ok, query}
      end
    else
      {:error, %{code: :invalid_discovery_query, reason: :invalid_encoding}}
    end
  end

  defp validate_query(_query),
    do: {:error, %{code: :invalid_discovery_query, reason: :required_string}}

  defp validate_limit(limit) when is_integer(limit) and limit in 1..@max_limit,
    do: {:ok, limit, nil}

  defp validate_limit(limit) when is_integer(limit) and limit > @max_limit do
    {:ok, @max_limit,
     %{
       code: :discovery_limit_clamped,
       requested: limit,
       applied: @max_limit
     }}
  end

  defp validate_limit(limit),
    do: {:error, %{code: :invalid_discovery_limit, value: limit, allowed: 1..@max_limit}}

  defp validate_kinds(nil, "*"), do: {:ok, ["module"]}
  defp validate_kinds(nil, _query), do: {:ok, @allowed_kinds}

  defp validate_kinds(kinds, _query) when is_list(kinds) do
    invalid = Enum.reject(kinds, &(&1 in @allowed_kinds))

    cond do
      kinds == [] ->
        {:error, %{code: :invalid_discovery_kinds, reason: :at_least_one_required}}

      invalid != [] ->
        {:error,
         %{
           code: :invalid_discovery_kinds,
           kinds: Enum.uniq(invalid),
           allowed: @allowed_kinds
         }}

      length(kinds) != length(Enum.uniq(kinds)) ->
        {:error, %{code: :invalid_discovery_kinds, reason: :duplicates}}

      true ->
        {:ok, kinds}
    end
  end

  defp validate_kinds(kinds, _query),
    do: {:error, %{code: :invalid_discovery_kinds, kinds: kinds, allowed: @allowed_kinds}}

  defp discover(graph, revision, request) do
    candidates = candidates(graph, request.kinds)
    matches = ranked_matches(candidates, request.query)
    pool = strongest_matches(matches, request.query)
    returned = Enum.take(pool, request.limit)

    %{
      base_revision: revision,
      query: request.query,
      status: status(pool),
      results: Enum.map(returned, &summarize(graph, &1)),
      suggestions: suggestions(candidates, request.query, pool),
      truncated: length(pool) > request.limit,
      warnings: List.wrap(request.warning)
    }
  end

  defp candidates(graph, kinds) do
    graph.nodes
    |> Map.values()
    |> Enum.flat_map(fn
      %Module{} = module -> if "module" in kinds, do: [candidate(module)], else: []
      %Function{} = function -> if "function" in kinds, do: [candidate(function)], else: []
      _node -> []
    end)
  end

  defp candidate(%Module{} = module) do
    %{
      node: module,
      kind: :module,
      focus: module.id,
      name: module.name,
      documentation: module.documentation
    }
  end

  defp candidate(%Function{} = function) do
    %{
      node: function,
      kind: :function,
      focus: function.id,
      name: "#{function.module}.#{function.name}/#{function.arity}",
      documentation: function.documentation
    }
  end

  defp ranked_matches(candidates, "*") do
    candidates
    |> Enum.map(&Map.merge(&1, %{rank: 4, match: :namespace_listing}))
    |> Enum.sort_by(&{&1.rank, &1.focus})
  end

  defp ranked_matches(candidates, query) do
    candidates
    |> Enum.flat_map(fn candidate ->
      case rank(candidate, query) do
        nil -> []
        {rank, reason} -> [Map.merge(candidate, %{rank: rank, match: reason})]
      end
    end)
    |> Enum.sort_by(&{&1.rank, &1.focus})
  end

  defp rank(candidate, query) do
    normalized_query = normalize(query)
    name_query = strip_focus(normalized_query)
    name = normalize(candidate.name)

    cond do
      normalize(candidate.focus) == normalized_query -> {0, :exact_focus}
      exact_suffix?(name, name_query) -> {1, :exact_suffix}
      name_prefix?(name, name_query) -> {2, :name_prefix}
      documentation_match?(candidate.documentation, name_query) -> {3, :documentation}
      true -> nil
    end
  end

  defp exact_suffix?(name, query), do: name == query or String.ends_with?(name, "." <> query)

  defp name_prefix?(name, query) do
    String.starts_with?(name, query) or
      (not String.contains?(query, ".") and
         String.starts_with?(local_name(name), local_name(query)))
  end

  defp documentation_match?(documentation, query) when is_binary(documentation) do
    tokens = tokens(query)
    document_tokens = documentation |> normalize() |> tokens() |> MapSet.new()
    tokens != [] and Enum.all?(tokens, &MapSet.member?(document_tokens, &1))
  end

  defp documentation_match?(_documentation, _query), do: false

  defp strongest_matches([], _query), do: []
  defp strongest_matches(matches, "*"), do: matches

  defp strongest_matches([%{rank: rank} | _rest] = matches, _query) when rank in 0..1,
    do: Enum.take_while(matches, &(&1.rank == rank))

  defp strongest_matches(matches, _query), do: matches

  defp status([]), do: :not_found

  defp status([%{rank: rank}]) when rank in 0..1, do: :exact

  defp status([%{rank: rank}, %{rank: rank} | _rest]) when rank in 0..1,
    do: :ambiguous

  defp status(_matches), do: :matches

  defp summarize(graph, %{node: %Module{} = module} = candidate) do
    module_name = module.name

    functions =
      graph.nodes
      |> Map.values()
      |> Enum.filter(&match?(%Function{module: ^module_name, visibility: :public}, &1))
      |> Enum.sort_by(& &1.id)

    %{
      kind: :module,
      focus: module.id,
      path: module.source.path,
      start_line: module.source.start_line,
      doc: compact_doc(module.documentation),
      match: candidate.match,
      public_functions:
        functions |> Enum.take(@max_module_functions) |> Enum.map(&function_summary(graph, &1)),
      public_functions_truncated: length(functions) > @max_module_functions
    }
  end

  defp summarize(graph, %{node: %Function{} = function} = candidate) do
    graph
    |> function_summary(function)
    |> Map.put(:match, candidate.match)
  end

  defp function_summary(graph, %Function{} = function) do
    %{
      kind: :function,
      focus: function.id,
      signature: "#{function.name}/#{function.arity}",
      path: function.source.path,
      start_line: function.source.start_line,
      visibility: function.visibility,
      doc: compact_doc(function.documentation),
      caller_count: graph |> Graph.callers(function.id) |> length(),
      callee_count: graph |> Graph.callees(function.id) |> length(),
      test_count: related_test_count(graph, function.id)
    }
  end

  defp related_test_count(graph, function_id) do
    graph.edges
    |> Enum.filter(&(&1.kind == :tested_by and &1.from == function_id))
    |> Enum.map(& &1.to)
    |> Enum.uniq()
    |> length()
  end

  defp compact_doc(false), do: false
  defp compact_doc(nil), do: nil

  defp compact_doc(documentation) do
    compact = documentation |> String.replace(~r/\s+/u, " ") |> String.trim()

    if String.length(compact) <= @max_doc_chars,
      do: compact,
      else: String.slice(compact, 0, @max_doc_chars - 1) <> "…"
  end

  defp suggestions(_candidates, _query, [_match | _rest]), do: []

  defp suggestions(candidates, query, []) do
    query_local = query |> normalize() |> strip_focus() |> local_name()

    candidates
    |> Enum.filter(&(local_name(normalize(&1.name)) == query_local))
    |> Enum.sort_by(& &1.focus)
    |> Enum.take(5)
    |> Enum.map(fn candidate ->
      %{
        kind: candidate.kind,
        focus: candidate.focus,
        path: candidate.node.source.path,
        start_line: candidate.node.source.start_line
      }
    end)
  end

  defp ensure_same_revision(%{revision: %{working_hash: hash}}, hash), do: :ok
  defp ensure_same_revision(_graph, _expected), do: {:error, %{code: :stale_source_during_query}}

  defp normalize(value), do: String.downcase(value)

  defp strip_focus(value) do
    value
    |> String.replace_prefix("module:", "")
    |> String.replace_prefix("function:", "")
  end

  defp local_name(value), do: value |> String.split(".") |> List.last()

  defp tokens(value), do: String.split(value, ~r/[^[:alnum:]_]+/u, trim: true)

  defp focus_kind_prefix("module:" <> _rest), do: "module:"
  defp focus_kind_prefix("function:" <> _rest), do: "function:"
  defp focus_kind_prefix("test:" <> _rest), do: "test:"
  defp focus_kind_prefix(_focus), do: ""

  defp suggestion_local_name(focus),
    do: focus |> strip_focus() |> local_name() |> normalize()
end
