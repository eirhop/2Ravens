defmodule TwoRavens.Source.Parser do
  @moduledoc false

  alias TwoRavens.Evidence
  alias TwoRavens.Identity
  alias TwoRavens.Repository
  alias TwoRavens.Source.Clause
  alias TwoRavens.Source.Facts
  alias TwoRavens.Source.Fragment
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.Module
  alias TwoRavens.Source.Range
  alias TwoRavens.Source.Subset
  alias TwoRavens.Source.Syntax
  alias TwoRavens.Source.Test

  @max_source_bytes 1_000_000

  @spec parse(String.t(), String.t()) :: {:ok, Fragment.t()} | {:error, map()}
  def parse(path, source)
      when is_binary(path) and is_binary(source) and byte_size(source) <= @max_source_bytes do
    options = [columns: true, token_metadata: true]

    with {:ok, ast} <- parse_quoted(source, options),
         {:ok, module_name, body, module_meta} <- module_ast(ast),
         {:ok, entries, unsupported} <- top_level_entries(body) do
      evidence = Evidence.derived_source()
      lines = String.split(source, "\n", trim: false)
      module_end_line = Range.final_module_end_line(lines)

      module_range =
        Range.new(path, 1, 1, module_end_line, Range.line_column(lines, module_end_line))

      source_module = %Module{
        id: Identity.module(module_name),
        name: module_name,
        source: Range.put_start(module_range, module_meta),
        evidence: evidence
      }

      {functions, tests} =
        derive_entries(entries, module_name, path, source, lines, evidence)

      {:ok,
       %Fragment{
         path: path,
         hash: Repository.hash(source),
         module: source_module,
         functions: functions,
         tests: tests,
         unsupported: unsupported
       }}
    end
  end

  def parse(path, source) when is_binary(path) and is_binary(source),
    do: {:error, %{code: :source_too_large, limit_bytes: @max_source_bytes}}

  def parse(path, source),
    do: {:error, %{code: :invalid_argument, arguments: %{path: path, source: source}}}

  defp parse_quoted(source, options) do
    case Code.string_to_quoted(source, options) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, %{code: :invalid_source, reason: inspect(reason)}}
    end
  end

  defp module_ast({:defmodule, meta, [alias_ast, [do: body]]}) do
    case Syntax.alias_name(alias_ast) do
      {:ok, name} -> {:ok, name, body, meta}
      :error -> {:error, %{code: :unsupported_module_name}}
    end
  end

  defp module_ast(_ast), do: {:error, %{code: :unsupported_source, reason: :one_module_required}}

  defp top_level_entries(body) do
    body
    |> Syntax.block_entries()
    |> Enum.reduce({[], []}, fn entry, {accepted, unsupported} ->
      case Subset.top_level(entry) do
        :supported -> {[entry | accepted], unsupported}
        {:unsupported, description} -> {accepted, [description | unsupported]}
      end
    end)
    |> then(fn {accepted, unsupported} ->
      accepted = Enum.reverse(accepted)
      semantic = Enum.flat_map(accepted, &Subset.inside/1)
      {:ok, accepted, Enum.reverse(unsupported) ++ semantic}
    end)
  end

  defp derive_entries(entries, module_name, path, source, lines, evidence) do
    aliases = aliases(entries)
    imports = imports(entries)

    positioned =
      entries
      |> Enum.filter(&match?({kind, _, _} when kind in [:def, :test], &1))
      |> Enum.map(&{Range.line_of(&1), &1})
      |> Enum.sort_by(&elem(&1, 0))

    module_end_line = Range.final_module_end_line(lines)

    ranges =
      positioned
      |> Enum.with_index()
      |> Enum.map(fn {{line, ast}, index} ->
        next_line = positioned |> Enum.at(index + 1, {module_end_line, nil}) |> elem(0)
        {end_line, end_column} = Range.ast_end(ast, lines, max(line, next_line - 1))

        {ast,
         Range.new(
           path,
           line,
           Range.column_of(ast),
           end_line,
           end_column
         )}
      end)

    clauses =
      ranges
      |> Enum.filter(fn {ast, _range} -> match?({:def, _, _}, ast) end)
      |> Enum.map(fn {ast, source_range} ->
        clause_seed(ast, module_name, aliases, imports, path, source, source_range, evidence)
      end)

    functions = build_functions(clauses, evidence)

    tests =
      ranges
      |> Enum.filter(fn {ast, _range} -> match?({:test, _, _}, ast) end)
      |> Enum.map(fn {ast, source_range} ->
        build_test(ast, module_name, aliases, imports, path, source_range, evidence)
      end)

    {functions, tests}
  end

  defp clause_seed(
         {:def, _meta, [head, body_keyword]},
         module_name,
         aliases,
         imports,
         path,
         source,
         source_range,
         evidence
       ) do
    {name, args, guard} = Syntax.function_head(head)
    function_id = Identity.function(module_name, Atom.to_string(name), length(args))

    clause_fingerprint =
      Identity.fingerprint({Enum.map(args, &Macro.to_string/1), Syntax.normalize_ast(guard)})

    calls =
      Facts.calls(
        Keyword.fetch!(body_keyword, :do),
        module_name,
        aliases,
        imports,
        function_id,
        path,
        evidence
      )

    comparisons =
      Facts.comparisons(
        guard,
        function_id,
        clause_fingerprint,
        path,
        source,
        evidence
      )

    %{
      function_id: function_id,
      module: module_name,
      name: Atom.to_string(name),
      arity: length(args),
      patterns: Enum.map(args, &Macro.to_string/1),
      guard: guard && Macro.to_string(guard),
      fingerprint: clause_fingerprint,
      calls: calls,
      comparisons: comparisons,
      source: source_range
    }
  end

  defp build_functions(seeds, evidence) do
    seeds
    |> Enum.group_by(& &1.function_id)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {_function_id, grouped} ->
      grouped = Enum.sort_by(grouped, & &1.source.start_line)
      first = hd(grouped)
      clauses = build_clauses(grouped, evidence)

      source = %{
        hd(clauses).source
        | end_line: List.last(clauses).source.end_line,
          end_column: List.last(clauses).source.end_column
      }

      %Function{
        id: first.function_id,
        module: first.module,
        name: first.name,
        arity: first.arity,
        clauses: clauses,
        source: source,
        evidence: evidence
      }
    end)
  end

  defp build_clauses(grouped, evidence) do
    grouped
    |> Enum.with_index(1)
    |> Enum.map(fn {seed, ordinal} -> build_clause(seed, ordinal, evidence) end)
  end

  defp build_clause(seed, ordinal, evidence) do
    clause_id = "clause:#{seed.function_id}:#{ordinal}:#{seed.fingerprint}"

    comparisons =
      seed.comparisons
      |> Enum.with_index(1)
      |> Enum.map(fn {comparison, index} ->
        %{
          comparison
          | id: "comparison:#{clause_id}:#{index}:#{comparison.fingerprint}",
            clause_id: clause_id
        }
      end)

    %Clause{
      id: clause_id,
      function_id: seed.function_id,
      ordinal: ordinal,
      fingerprint: seed.fingerprint,
      patterns: seed.patterns,
      guard: seed.guard,
      calls: seed.calls,
      comparisons: comparisons,
      source: seed.source,
      evidence: evidence
    }
  end

  defp build_test(
         {:test, _meta, [name, body_keyword]},
         module_name,
         aliases,
         imports,
         path,
         source_range,
         evidence
       ) do
    name = if is_binary(name), do: name, else: Macro.to_string(name)
    id = "test:#{module_name}:#{Identity.fingerprint(name)}"

    calls =
      Facts.calls(
        Keyword.fetch!(body_keyword, :do),
        module_name,
        aliases,
        imports,
        id,
        path,
        evidence
      )

    %Test{
      id: id,
      module: module_name,
      name: name,
      calls: calls,
      source: source_range,
      evidence: evidence
    }
  end

  defp aliases(entries) do
    entries
    |> Enum.flat_map(fn
      {:alias, _meta, [alias_ast | options]} ->
        with {:ok, full} <- Syntax.alias_name(alias_ast),
             {:ok, short} <- alias_short_name(full, List.flatten(options)) do
          [{short, full}]
        else
          _ -> []
        end

      _other ->
        []
    end)
    |> Map.new()
  end

  defp alias_short_name(full, options) do
    case Keyword.get(options, :as) do
      nil -> {:ok, full |> String.split(".") |> List.last()}
      as_ast -> Syntax.alias_name(as_ast)
    end
  end

  defp imports(entries) do
    entries
    |> Enum.flat_map(fn
      {:import, _meta, [alias_ast | _options]} ->
        case Syntax.alias_name(alias_ast) do
          {:ok, module} -> [module]
          :error -> []
        end

      _other ->
        []
    end)
    |> Enum.sort()
  end
end
