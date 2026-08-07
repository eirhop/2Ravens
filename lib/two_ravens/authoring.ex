defmodule TwoRavens.Authoring do
  @moduledoc "Documented ordinary Elixir APIs for the greenfield authoring workflow."

  alias TwoRavens.Authoring.Candidate
  alias TwoRavens.Authoring.Options
  alias TwoRavens.Authoring.Pipeline
  alias TwoRavens.CreateFunction
  alias TwoRavens.CreateModule
  alias TwoRavens.Manifest
  alias TwoRavens.Project
  alias TwoRavens.SetComparison

  @doc """
  Initializes the small versioned management manifest in an existing Mix project.

  ## Examples

      iex> {:error, %{code: :missing_project}} = TwoRavens.Authoring.init("missing")

  """
  @spec init(Path.t()) :: {:ok, Manifest.t()} | {:error, map()}
  def init(root) when is_binary(root) do
    with {:ok, project} <- Project.open(root) do
      Manifest.init(project)
    end
  end

  def init(root), do: invalid_arguments(%{root: root})

  @doc "Creates a normal or ExUnit module candidate; writes only with `apply: true`."
  @spec create_module(Path.t(), String.t(), keyword()) ::
          {:ok, Candidate.t()} | {:error, map()}
  def create_module(root, module, options \\ [])

  def create_module(root, module, options) when is_binary(root) and is_binary(module) do
    with {:ok, options} <-
           Options.validate(options,
             apply: {:boolean, false},
             test: {:boolean, false},
             source: {:binary, ""}
           ),
         {:ok, proposal} <- CreateModule.build(root, module, options) do
      Pipeline.finish(proposal, options.apply)
    end
  end

  def create_module(root, module, _options),
    do: invalid_arguments(%{root: root, module: module})

  @doc "Adds one function name and arity, possibly with several clauses, from ordinary Elixir."
  @spec create_function(Path.t(), String.t(), String.t(), keyword()) ::
          {:ok, Candidate.t()} | {:error, map()}
  def create_function(root, module, fragment, options \\ [])

  def create_function(root, module, fragment, options)
      when is_binary(root) and is_binary(module) and is_binary(fragment) do
    with {:ok, options} <- Options.validate(options, apply: {:boolean, false}),
         {:ok, proposal} <- CreateFunction.build(root, module, fragment) do
      Pipeline.finish(proposal, options.apply)
    end
  end

  def create_function(root, module, fragment, _options),
    do: invalid_arguments(%{root: root, module: module, fragment: fragment})

  @doc "Changes only the comparison operator identified by a stateless handle."
  @spec set(Path.t(), String.t(), String.t(), keyword()) ::
          {:ok, Candidate.t()} | {:error, map()}
  def set(root, target, operator, options \\ [])

  def set(root, target, operator, options)
      when is_binary(root) and is_binary(target) and is_binary(operator) do
    with {:ok, options} <- Options.validate(options, apply: {:boolean, false}),
         {:ok, proposal} <- SetComparison.build(root, target, operator) do
      Pipeline.finish(proposal, options.apply)
    end
  end

  def set(root, target, operator, _options),
    do: invalid_arguments(%{root: root, target: target, operator: operator})

  defp invalid_arguments(arguments),
    do: {:error, %{code: :invalid_arguments, arguments: arguments}}
end
