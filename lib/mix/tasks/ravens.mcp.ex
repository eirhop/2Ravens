defmodule Mix.Tasks.Ravens.Mcp do
  @moduledoc false
  use Mix.Task

  alias TwoRavens.MCP.Server

  @shortdoc "Runs the project-bound 2Ravens STDIO MCP server"

  @impl Mix.Task
  def run(argv) do
    case OptionParser.parse(argv, strict: [root: :string]) do
      {[root: root], [], []} ->
        case Server.run(root) do
          :ok -> :ok
          {:error, reason} -> Mix.raise("cannot start MCP server: #{inspect(reason)}")
        end

      _other ->
        Mix.raise("usage: mix ravens.mcp --root PATH")
    end
  end
end
