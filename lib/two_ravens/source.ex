defmodule TwoRavens.Source do
  @moduledoc "Elixir-native read-back for the managed greenfield source subset."

  alias TwoRavens.Identity
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.Source.Fragment
  alias TwoRavens.Source.Loader
  alias TwoRavens.Source.Parser
  alias TwoRavens.Source.Range
  alias TwoRavens.SourceRange

  @doc "Rebuilds a graph from all and only paths in the management manifest."
  @spec rebuild(Path.t()) :: {:ok, TwoRavens.Graph.t()} | {:error, map()}
  defdelegate rebuild(root), to: Loader

  @doc "Rebuilds a graph using an already validated project and manifest."
  @spec rebuild(Project.t(), Manifest.t()) :: {:ok, TwoRavens.Graph.t()} | {:error, map()}
  defdelegate rebuild(project, manifest), to: Loader

  @doc "Rebuilds while substituting in-memory candidate source for selected managed paths."
  @spec rebuild_with(Project.t(), Manifest.t(), %{String.t() => String.t()}) ::
          {:ok, TwoRavens.Graph.t()} | {:error, map()}
  defdelegate rebuild_with(project, manifest, candidate_files), to: Loader

  @doc "Computes managed file hashes without parsing or rebuilding the graph."
  @spec revision(Project.t(), Manifest.t()) ::
          {:ok, TwoRavens.Repository.Revision.t()} | {:error, map()}
  defdelegate revision(project, manifest), to: Loader

  @doc "Parses one managed file without evaluating application source."
  @spec parse(String.t(), String.t()) :: {:ok, Fragment.t()} | {:error, map()}
  defdelegate parse(path, source), to: Parser

  @doc "Returns the exact source selected by a source range."
  @spec select(String.t(), SourceRange.t()) :: String.t()
  defdelegate select(source, range), to: Range

  @doc "Returns a canonical module identity."
  @spec module_id(String.t()) :: String.t()
  defdelegate module_id(module), to: Identity, as: :module

  @doc "Returns a canonical function identity."
  @spec function_id(String.t(), String.t(), non_neg_integer()) :: String.t()
  defdelegate function_id(module, name, arity), to: Identity, as: :function

  @doc "Returns a deterministic structural fingerprint."
  @spec fingerprint(term()) :: String.t()
  defdelegate fingerprint(term), to: Identity
end
