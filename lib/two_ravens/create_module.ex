defmodule TwoRavens.CreateModule do
  @moduledoc false

  alias TwoRavens.Authoring.Proposal
  alias TwoRavens.Authoring.Support
  alias TwoRavens.Identity
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Source

  @spec build(Path.t(), String.t(), map()) :: {:ok, Proposal.t()} | {:error, map()}
  def build(root, module, options) do
    with {:ok, project} <- Project.open(root),
         {:ok, manifest} <- Manifest.load(project),
         {:ok, manifest_hash} <- Manifest.content_hash(project),
         {:ok, base_graph} <- Source.rebuild(project, manifest),
         {:ok, path} <- Project.module_path(module, options.test),
         :ok <- reject_path_collision(project, path),
         :ok <- reject_module_collision(project, base_graph, module),
         :ok <- validate_targets(base_graph, options),
         {:ok, source} <- module_source(module, options.source, options.test, path),
         {:ok, parsed} <- Source.parse(path, source),
         :ok <- Support.reject_unsupported(parsed.unsupported),
         {:ok, candidate_manifest} <- Manifest.add(manifest, path),
         {:ok, proposed_graph} <-
           Source.rebuild_with(project, candidate_manifest, %{path => source}),
         :ok <- Support.reject_path_unsupported(proposed_graph, path) do
      {:ok,
       %Proposal{
         kind: :create_module,
         project: project,
         files: %{path => source},
         before_files: %{},
         base_hashes: Map.put(base_graph.revision.file_hashes, path, nil),
         base_working_hash: base_graph.revision.working_hash,
         manifest: candidate_manifest,
         manifest_hash: manifest_hash,
         graph: proposed_graph,
         details: %{module: module, path: path, test: options.test},
         semantic: %{
           subject: Identity.module(module),
           intent: options.intent,
           intent_kind: :purpose,
           targets: options.for
         }
       }}
    end
  end

  defp module_source(module, fragment, test?, path) do
    description =
      if test?, do: "Managed ExUnit tests for #{module}.", else: "Managed module #{module}."

    body = String.trim(fragment)
    body = if body == "", do: "", else: "\n" <> Support.indent(body) <> "\n"

    source =
      "defmodule #{module} do\n" <>
        "  @moduledoc \"#{description}\"\n" <>
        body <>
        "end\n"

    Support.format(source, path)
  end

  defp reject_path_collision(project, path) do
    with {:ok, absolute} <- Project.resolve(project, path) do
      if File.exists?(absolute), do: {:error, %{code: :source_collision, path: path}}, else: :ok
    end
  end

  defp reject_module_collision(project, graph, module) do
    if Map.has_key?(graph.nodes, Identity.module(module)),
      do: {:error, %{code: :module_collision, module: module}},
      else: reject_unmanaged_module_collision(project, module)
  end

  defp validate_targets(_graph, %{test: false, for: []}), do: :ok

  defp validate_targets(_graph, %{test: false}) do
    {:error, %{code: :intended_targets_require_test_module}}
  end

  defp validate_targets(graph, %{for: targets}) do
    case Enum.reject(targets, &Map.has_key?(graph.nodes, &1)) do
      [] -> :ok
      unknown -> {:error, %{code: :unknown_semantic_targets, targets: Enum.sort(unknown)}}
    end
  end

  defp reject_unmanaged_module_collision(project, module) do
    declaration = Regex.compile!("(?m)^\\s*defmodule\\s+#{Regex.escape(module)}\\s+do\\b")

    ["lib/**/*.ex", "test/**/*.exs"]
    |> Enum.flat_map(&Path.wildcard(Path.join(project.root, &1)))
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn path, :ok ->
      scan_unmanaged_file(path, declaration, module)
    end)
  end

  defp scan_unmanaged_file(path, declaration, module) do
    with {:ok, %File.Stat{type: type}} <- File.lstat(path),
         false <- type == :symlink,
         {:ok, source} <- File.read(path) do
      collision_result(source, declaration, module)
    else
      true ->
        {:halt, {:error, %{code: :unsafe_unmanaged_path, path: path, reason: :symbolic_link}}}

      {:error, reason} ->
        {:halt, {:error, %{code: :unmanaged_source_read_failed, path: path, reason: reason}}}
    end
  end

  defp collision_result(source, declaration, module) do
    if Regex.match?(declaration, source),
      do: {:halt, {:error, %{code: :module_collision, module: module}}},
      else: {:cont, :ok}
  end
end
