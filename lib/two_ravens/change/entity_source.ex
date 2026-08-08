defmodule TwoRavens.Change.EntitySource do
  @moduledoc false

  alias TwoRavens.Authoring.Support
  alias TwoRavens.Graph
  alias TwoRavens.Repository
  alias TwoRavens.Source
  alias TwoRavens.Source.Clause
  alias TwoRavens.Source.Function
  alias TwoRavens.Source.ModuleForm
  alias TwoRavens.Source.Test

  @type state :: %{files: %{String.t() => String.t() | nil}, manifest: TwoRavens.Manifest.t()}

  @spec locate(Graph.t(), %{String.t() => String.t()}, String.t()) ::
          {:ok, map()} | {:error, map()}
  def locate(graph, files, "module:" <> name = id) do
    case Enum.find(graph.fragments, fn {_path, fragment} -> fragment.module.id == id end) do
      {path, _fragment} ->
        {:ok, %{kind: :module, id: id, module: name, path: path, source: files[path]}}

      nil ->
        {:error, %{code: :entity_not_found, target: id}}
    end
  end

  def locate(graph, files, "function:" <> _rest = id) do
    case Map.get(graph.nodes, id) do
      %Function{} = function -> ranged(files, function.source, :function, id, function.module)
      _other -> {:error, %{code: :entity_not_found, target: id}}
    end
  end

  def locate(graph, files, "clause:" <> _rest = id) do
    case Map.get(graph.nodes, id) do
      %Clause{} = clause ->
        module = function_module(graph, clause.function_id)
        ranged(files, clause.source, :clause, id, module)

      _other ->
        {:error, %{code: :entity_not_found, target: id}}
    end
  end

  def locate(graph, files, "module_form:" <> _rest = id) do
    case Map.get(graph.nodes, id) do
      %ModuleForm{} = form -> ranged(files, form.source, :module_form, id, form.module)
      _other -> {:error, %{code: :entity_not_found, target: id}}
    end
  end

  def locate(graph, files, "test:" <> _rest = id) do
    case Map.get(graph.nodes, id) do
      %Test{} = test -> ranged(files, test.source, :test, id, test.module, %{name: test.name})
      _other -> {:error, %{code: :entity_not_found, target: id}}
    end
  end

  def locate(_graph, _files, target),
    do: {:error, %{code: :unsupported_entity_target, target: target}}

  @spec replace_fragment(%{String.t() => String.t()}, map(), String.t()) ::
          {:ok, %{String.t() => String.t()}} | {:error, map()}
  def replace_fragment(files, entity, replacement) do
    source = Map.fetch!(files, entity.path)
    lines = String.split(source, "\n", trim: false)
    first = entity.start_line - 1
    count = entity.end_line - entity.start_line + 1
    replacement_lines = String.split(String.trim(replacement), "\n", trim: false)

    changed =
      lines
      |> Enum.take(first)
      |> Kernel.++(replacement_lines)
      |> Kernel.++(Enum.drop(lines, first + count))
      |> Enum.join("\n")

    Support.format(changed, entity.path)
    |> case do
      {:ok, formatted} -> {:ok, Map.put(files, entity.path, formatted)}
      error -> error
    end
  end

  @spec delete_fragment(%{String.t() => String.t()}, map()) ::
          {:ok, %{String.t() => String.t()}} | {:error, map()}
  def delete_fragment(files, entity), do: replace_fragment(files, entity, "")

  @spec append_to_module(%{String.t() => String.t()}, map(), String.t()) ::
          {:ok, %{String.t() => String.t()}} | {:error, map()}
  def append_to_module(files, module_entity, fragment) do
    source = Map.fetch!(files, module_entity.path)
    insertion = "\n" <> Support.indent(String.trim(fragment)) <> "\n"

    if Regex.match?(~r/\nend\s*\z/, source) do
      changed = Regex.replace(~r/\nend\s*\z/, source, insertion <> "end\n")

      with {:ok, formatted} <- Support.format(changed, module_entity.path) do
        {:ok, Map.put(files, module_entity.path, formatted)}
      end
    else
      {:error, %{code: :module_end_not_found, target: module_entity.id}}
    end
  end

  @spec insert_clause(%{String.t() => String.t()}, map(), map(), :before | :after) ::
          {:ok, %{String.t() => String.t()}} | {:error, map()}
  def insert_clause(files, anchor, clause, side) do
    source = Map.fetch!(files, anchor.path)
    lines = String.split(source, "\n", trim: false)
    at = if side == :before, do: anchor.start_line - 1, else: anchor.end_line
    insertion = String.split(String.trim(clause.text), "\n", trim: false) ++ [""]
    changed = (Enum.take(lines, at) ++ insertion ++ Enum.drop(lines, at)) |> Enum.join("\n")

    with {:ok, formatted} <- Support.format(changed, anchor.path) do
      {:ok, Map.put(files, anchor.path, formatted)}
    end
  end

  @spec fragment_hash(map()) :: String.t()
  def fragment_hash(entity), do: Repository.hash(entity.source)

  @spec validate_function(String.t()) :: {:ok, Function.t()} | {:error, map()}
  def validate_function(text) do
    wrapper = "defmodule TwoRavens.Fragment do\n#{Support.indent(String.trim(text))}\nend\n"

    with {:ok, source} <- Support.format(wrapper, "fragment.ex"),
         {:ok, fragment} <- Source.parse("fragment.ex", source),
         [%Function{} = function] <- fragment.functions,
         :ok <- function_only(fragment) do
      {:ok, function}
    else
      [] ->
        {:error, %{code: :invalid_function_fragment, reason: :function_required}}

      [_first | _rest] ->
        {:error, %{code: :invalid_function_fragment, reason: :one_identity_required}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp function_only(fragment) do
    if fragment.module.documentation == nil and fragment.module_forms == [] and
         fragment.tests == [] do
      :ok
    else
      {:error, %{code: :invalid_function_fragment, reason: :function_only_required}}
    end
  end

  @spec validate_test(String.t()) :: {:ok, Test.t()} | {:error, map()}
  def validate_test(text) when is_binary(text) do
    wrapper =
      "defmodule TwoRavens.TestFragment do\n  use ExUnit.Case\n#{Support.indent(String.trim(text))}\nend\n"

    with {:ok, source} <- Support.format(wrapper, "test_fragment.exs"),
         {:ok, fragment} <- Source.parse("test_fragment.exs", source),
         [%Test{} = test] <- fragment.tests,
         :ok <- test_only(fragment) do
      {:ok, test}
    else
      [] -> {:error, %{code: :invalid_test_fragment, reason: :test_required}}
      [_first | _rest] -> {:error, %{code: :invalid_test_fragment, reason: :one_test_required}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec validate_test(String.t(), String.t()) :: {:ok, Test.t()} | {:error, map()}
  def validate_test(text, expected_name) when is_binary(text) and is_binary(expected_name) do
    with {:ok, test} <- validate_test(text),
         true <- test.name == expected_name do
      {:ok, test}
    else
      false -> {:error, %{code: :replacement_identity_mismatch}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp test_only(fragment) do
    allowed_forms? =
      Enum.all?(fragment.module_forms, &String.starts_with?(&1.form, "use ExUnit.Case"))

    if fragment.module.documentation == nil and fragment.functions == [] and allowed_forms? do
      :ok
    else
      {:error, %{code: :invalid_test_fragment, reason: :test_only_required}}
    end
  end

  @spec validate_clause(String.t(), Function.t()) :: {:ok, map()} | {:error, map()}
  def validate_clause(text, target) do
    with {:ok, function} <- validate_function(text),
         true <- {function.name, function.arity} == {target.name, target.arity},
         [clause] <- function.clauses do
      {:ok, %{text: text, clause: clause}}
    else
      false -> {:error, %{code: :clause_identity_mismatch, target: target.id}}
      [_first | _rest] -> {:error, %{code: :one_clause_required}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ranged(files, range, kind, id, module) do
    ranged(files, range, kind, id, module, %{})
  end

  defp ranged(files, range, kind, id, module, attributes) do
    source = Map.fetch!(files, range.path)

    entity = %{
      kind: kind,
      id: id,
      module: module,
      path: range.path,
      start_line: range.start_line,
      end_line: range.end_line,
      source: Source.select(source, range)
    }

    {:ok, Map.merge(entity, attributes)}
  end

  defp function_module(%Graph{} = graph, id) do
    case Map.get(graph.nodes, id) do
      %Function{module: module} -> module
      _other -> nil
    end
  end
end
