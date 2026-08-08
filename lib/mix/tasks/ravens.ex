defmodule Mix.Tasks.Ravens do
  use Mix.Task

  @shortdoc "Authors and queries 2Ravens-managed Elixir entities"

  @moduledoc """
  Thin CLI adapter for `TwoRavens.Authoring`, `TwoRavens.Change`, and
  `TwoRavens.Context`.

      mix ravens init --root PATH
      mix ravens create module MODULE --root PATH [--test] [--intent TEXT] [--for TARGET]
      mix ravens create function MODULE --root PATH --stdin [--intent TEXT] [--apply]
      mix ravens context function:MODULE.name/arity --root PATH [--include FIELDS]
      mix ravens set HANDLE.operator OPERATOR --root PATH [--intent TEXT] [--apply]
      mix ravens change --root PATH (--stdin | --request JSON_FILE)
      mix ravens draft-context DRAFT VERSION FOCUS --root PATH
      mix ravens revision --root PATH
      mix ravens entities --root PATH
  """

  alias TwoRavens.Authoring
  alias TwoRavens.Change
  alias TwoRavens.CLI
  alias TwoRavens.Context

  @switches [
    root: :string,
    apply: :boolean,
    test: :boolean,
    stdin: :boolean,
    for_edit: :boolean,
    intent: :string,
    for: :keep,
    include: :string,
    compact: :boolean,
    details: :boolean,
    request: :string
  ]

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
      intent: Keyword.get(options, :intent),
      for: Keyword.get_values(options, :for),
      apply: Keyword.get(options, :apply, false)
    )
    |> formatted(&CLI.candidate(&1, details: Keyword.get(options, :details, false)))
  end

  defp dispatch(["create", "function", module], root, options) do
    if Keyword.get(options, :stdin, false) do
      with {:ok, source} <- read_stdin() do
        Authoring.create_function(root, module, source,
          intent: Keyword.get(options, :intent),
          apply: Keyword.get(options, :apply, false)
        )
        |> formatted(&CLI.candidate(&1, details: Keyword.get(options, :details, false)))
      end
    else
      {:error, %{code: :stdin_required}}
    end
  end

  defp dispatch(["context", focus], root, options) do
    includes =
      case Keyword.get(options, :include) do
        nil -> []
        include -> [include]
      end

    Context.query(root, focus,
      for_edit: Keyword.get(options, :for_edit, false),
      include: includes,
      compact: Keyword.get(options, :compact, true),
      details: Keyword.get(options, :details, false)
    )
    |> formatted(&CLI.context(&1, details: Keyword.get(options, :details, false)))
  end

  defp dispatch(["set", target, operator], root, options) do
    Authoring.set(root, target, operator,
      intent: Keyword.get(options, :intent),
      apply: Keyword.get(options, :apply, false)
    )
    |> formatted(&CLI.candidate(&1, details: Keyword.get(options, :details, false)))
  end

  defp dispatch(["change"], root, options) do
    with {:ok, input} <- read_change_input(options),
         {:ok, request} <- CLI.decode_change(input) do
      Change.submit(root, request)
      |> formatted(&CLI.change/1)
    end
  end

  defp dispatch(["draft-context", draft, version, focus], root, _options) do
    case Integer.parse(version) do
      {parsed_version, ""} ->
        Change.draft_context(root, draft, parsed_version, focus)
        |> formatted(&CLI.draft_context/1)

      _other ->
        {:error, %{code: :invalid_draft_version, value: version}}
    end
  end

  defp dispatch(["revision"], root, _options) do
    Change.current_revision(root)
    |> formatted(&CLI.revision/1)
  end

  defp dispatch(["entities"], root, _options) do
    Change.entities(root)
    |> formatted(&CLI.entities/1)
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

  defp read_change_input(options) do
    case {Keyword.get(options, :stdin, false), Keyword.get(options, :request)} do
      {true, nil} -> read_stdin()
      {false, path} when is_binary(path) -> read_request(path)
      {false, nil} -> {:error, %{code: :change_input_required}}
      {true, _path} -> {:error, %{code: :conflicting_change_inputs}}
    end
  end

  defp read_request(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, %{code: :request_read_failed, path: path, reason: reason}}
    end
  end

  defp formatted({:ok, value}, formatter), do: {:ok, value, formatter}
  defp formatted({:error, reason}, _formatter), do: {:error, reason}
end
