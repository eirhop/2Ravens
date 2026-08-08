defmodule TwoRavens.Change.SourceBundle do
  @moduledoc false

  alias TwoRavens.Authoring.Support
  alias TwoRavens.Project
  alias TwoRavens.Source.Syntax

  @spec split(String.t()) :: {:ok, [map()]} | {:error, map()}
  def split(source) when is_binary(source) do
    with {:ok, ast} <- quoted(source),
         modules when modules != [] <- Syntax.block_entries(ast),
         true <- Enum.all?(modules, &match?({:defmodule, _, _}, &1)),
         {:ok, split} <- split_modules(modules) do
      {:ok, split}
    else
      [] -> {:error, %{code: :invalid_source_bundle, reason: :module_required}}
      false -> {:error, %{code: :invalid_source_bundle, reason: :only_modules_allowed}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp quoted(source) do
    case Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, %{code: :invalid_source, reason: inspect(reason)}}
    end
  end

  defp split_modules(modules) do
    modules
    |> Enum.reduce_while({:ok, []}, fn module_ast, {:ok, accepted} ->
      with {:ok, name} <- module_name(module_ast),
           {:ok, path} <- Project.module_path(name, test_module?(module_ast)),
           {:ok, source} <- Support.format(Macro.to_string(module_ast) <> "\n", path) do
        {:cont, {:ok, [%{module: name, path: path, source: source} | accepted]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, accepted} -> reject_duplicates(Enum.reverse(accepted))
      error -> error
    end
  end

  defp module_name({:defmodule, _meta, [alias_ast, [do: _body]]}) do
    case Syntax.alias_name(alias_ast) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, %{code: :unsupported_module_name}}
    end
  end

  defp test_module?({:defmodule, _meta, [_alias_ast, [do: body]]}) do
    body
    |> Syntax.block_entries()
    |> Enum.any?(&match?({:use, _, [{:__aliases__, _, [:ExUnit, :Case]} | _]}, &1))
  end

  defp reject_duplicates(modules) do
    duplicates =
      modules
      |> Enum.frequencies_by(& &1.module)
      |> Enum.filter(fn {_module, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates == [],
      do: {:ok, modules},
      else: {:error, %{code: :duplicate_module_identity, modules: Enum.sort(duplicates)}}
  end
end
