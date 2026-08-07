defmodule Mix.Tasks.Ravens do
  use Mix.Task

  @shortdoc "Authors and queries 2Ravens-managed greenfield Elixir source"

  @moduledoc """
  Thin CLI adapter for `TwoRavens.Authoring` and `TwoRavens.Context`.

      mix ravens init --root PATH
      mix ravens create module MODULE --root PATH [--test] [--stdin] [--apply]
      mix ravens create function MODULE --root PATH --stdin [--apply]
      mix ravens context function:MODULE.name/arity --root PATH --for-edit
      mix ravens set HANDLE.operator OPERATOR --root PATH [--apply]
  """

  alias TwoRavens.Authoring
  alias TwoRavens.CLI
  alias TwoRavens.Context

  @switches [root: :string, apply: :boolean, test: :boolean, stdin: :boolean, for_edit: :boolean]

  @impl Mix.Task
  def run(arguments) do
    {options, command, invalid} = OptionParser.parse(arguments, strict: @switches)

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    root = Keyword.get(options, :root) || Mix.raise("--root is required")

    result = dispatch(command, root, options)

    case result do
      {:ok, value, formatter} -> Mix.shell().info(formatter.(value))
      {:ok, value} -> Mix.shell().info(inspect(value))
      {:error, reason} -> Mix.raise(CLI.error(reason))
    end
  end

  defp dispatch(["init"], root, _options), do: Authoring.init(root)

  defp dispatch(["create", "module", module], root, options) do
    source = read_optional_stdin(options)

    Authoring.create_module(root, module,
      source: source,
      test: Keyword.get(options, :test, false),
      apply: Keyword.get(options, :apply, false)
    )
    |> formatted(&CLI.candidate/1)
  end

  defp dispatch(["create", "function", module], root, options) do
    if Keyword.get(options, :stdin, false) do
      with {:ok, source} <- read_stdin() do
        Authoring.create_function(root, module, source,
          apply: Keyword.get(options, :apply, false)
        )
        |> formatted(&CLI.candidate/1)
      end
    else
      {:error, %{code: :stdin_required}}
    end
  end

  defp dispatch(["context", focus], root, options) do
    Context.query(root, focus, for_edit: Keyword.get(options, :for_edit, false))
    |> formatted(&CLI.context/1)
  end

  defp dispatch(["set", target, operator], root, options) do
    Authoring.set(root, target, operator, apply: Keyword.get(options, :apply, false))
    |> formatted(&CLI.candidate/1)
  end

  defp dispatch(_command, _root, _options), do: {:error, %{code: :unsupported_command}}

  defp read_optional_stdin(options) do
    if Keyword.get(options, :stdin, false) do
      case read_stdin() do
        {:ok, source} -> source
        {:error, reason} -> Mix.raise(CLI.error(reason))
      end
    else
      ""
    end
  end

  defp read_stdin do
    case IO.binread(:stdio, :eof) do
      source when is_binary(source) -> {:ok, source}
      {:error, reason} -> {:error, %{code: :stdin_read_failed, reason: reason}}
    end
  end

  defp formatted({:ok, value}, formatter), do: {:ok, value, formatter}
  defp formatted({:error, reason}, _formatter), do: {:error, reason}
end
