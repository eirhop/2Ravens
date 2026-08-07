defmodule TwoRavens.CreateFunction do
  @moduledoc false

  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Authoring.Support
  alias TwoRavens.Identity
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Repository
  alias TwoRavens.Source
  alias TwoRavens.Source.Function

  @spec build(Path.t(), String.t(), String.t()) :: {:ok, Proposal.t()} | {:error, map()}
  def build(root, module, fragment) do
    with {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         {:ok, manifest_hash} <- Manifest.content_hash(project),
         {:ok, graph} <- Source.rebuild(project, manifest),
         {:ok, path, target_fragment} <- find_module(graph, module),
         :ok <- Support.reject_unsupported(target_fragment.unsupported),
         {:ok, added_function} <- validate_function_fragment(fragment),
         :ok <- reject_function_collision(graph, module, added_function),
         {:ok, before} <- Support.read_source(project, path),
         {:ok, source} <- insert_function(before, fragment, path),
         {:ok, proposed_graph} <- Source.rebuild_with(project, manifest, %{path => source}),
         :ok <- Support.reject_path_unsupported(proposed_graph, path) do
      function_id = Identity.function(module, added_function.name, added_function.arity)

      {:ok,
       %Proposal{
         kind: :create_function,
         project: project,
         files: %{path => source},
         before_files: %{path => before},
         base_hashes: %{path => Repository.hash(before)},
         manifest: manifest,
         manifest_hash: manifest_hash,
         graph: proposed_graph,
         details: %{function: function_id, path: path}
       }}
    end
  end

  defp validate_function_fragment(fragment) do
    wrapper = "defmodule TwoRavens.Fragment do\n#{Support.indent(String.trim(fragment))}\nend\n"

    with {:ok, source} <- Support.format(wrapper, "fragment.ex"),
         {:ok, parsed} <- Source.parse("fragment.ex", source),
         :ok <- Support.reject_unsupported(parsed.unsupported),
         :ok <- reject_tests(parsed.tests),
         [%Function{} = function] <- parsed.functions do
      {:ok, function}
    else
      [] ->
        {:error, %{code: :invalid_function_fragment, reason: :function_required}}

      [_first | _rest] ->
        {:error, %{code: :invalid_function_fragment, reason: :one_name_and_arity_required}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reject_tests([]), do: :ok

  defp reject_tests(_tests),
    do: {:error, %{code: :invalid_function_fragment, reason: :test_not_allowed}}

  defp insert_function(before, fragment, path) do
    insertion = "\n" <> Support.indent(String.trim(fragment)) <> "\n"

    if Regex.match?(~r/\nend\s*\z/, before) do
      changed = Regex.replace(~r/\nend\s*\z/, before, insertion <> "end\n")
      Support.format(changed, path)
    else
      {:error, %{code: :unsupported_source, reason: :module_end_not_found}}
    end
  end

  defp find_module(graph, module) do
    matches =
      Enum.filter(graph.fragments, fn {_path, fragment} -> fragment.module.name == module end)

    case matches do
      [{path, fragment}] -> {:ok, path, fragment}
      [] -> {:error, %{code: :managed_module_not_found, module: module}}
      _many -> {:error, %{code: :ambiguous_module, module: module}}
    end
  end

  defp reject_function_collision(graph, module, function) do
    id = Identity.function(module, function.name, function.arity)

    if Map.has_key?(graph.nodes, id),
      do: {:error, %{code: :function_collision, function: id}},
      else: :ok
  end
end
