defmodule TwoRavens.Authoring.Support do
  @moduledoc false

  alias TwoRavens.Project

  @spec reject_unsupported([String.t()]) :: :ok | {:error, map()}
  def reject_unsupported([]), do: :ok
  def reject_unsupported(facts), do: {:error, %{code: :unsupported_source, facts: facts}}

  @spec reject_path_unsupported(TwoRavens.Graph.t(), String.t()) :: :ok | {:error, map()}
  def reject_path_unsupported(graph, path) do
    facts = Enum.filter(graph.unsupported, &String.starts_with?(&1, "#{path}:"))
    reject_unsupported(facts)
  end

  @spec read_source(Project.t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  def read_source(%Project{} = project, path) do
    with {:ok, absolute} <- Project.resolve(project, path) do
      case File.read(absolute) do
        {:ok, source} ->
          {:ok, source}

        {:error, reason} ->
          {:error, %{code: :managed_file_read_failed, path: path, reason: reason}}
      end
    end
  end

  @spec format(String.t(), String.t()) :: {:ok, String.t()} | {:error, map()}
  def format(source, path) do
    {:ok, source |> Code.format_string!(file: path) |> IO.iodata_to_binary()}
  rescue
    error in [SyntaxError, TokenMissingError] ->
      {:error, %{code: :invalid_source, diagnostic: Exception.message(error)}}
  end

  @spec indent(String.t()) :: String.t()
  def indent(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &"  #{&1}")
  end
end
