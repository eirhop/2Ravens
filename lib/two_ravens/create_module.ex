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
         {:ok, path} <- Project.module_path(module, options.test),
         :ok <- reject_path_collision(project, path),
         :ok <- reject_module_collision(project, manifest, module),
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
         base_hashes: %{path => nil},
         manifest: candidate_manifest,
         manifest_hash: manifest_hash,
         graph: proposed_graph,
         details: %{module: module, path: path, test: options.test}
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

  defp reject_module_collision(project, manifest, module) do
    case Source.rebuild(project, manifest) do
      {:ok, graph} ->
        if Map.has_key?(graph.nodes, Identity.module(module)),
          do: {:error, %{code: :module_collision, module: module}},
          else: reject_unmanaged_module_collision(project, module)

      {:error, reason} ->
        {:error, reason}
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
