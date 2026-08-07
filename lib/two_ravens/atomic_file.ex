defmodule TwoRavens.AtomicFile do
  @moduledoc "Same-directory atomic replacement for one ordinary file."

  @doc "Writes complete content to a temporary sibling before renaming it into place."
  @spec write(Path.t(), iodata()) :: :ok | {:error, File.posix()}
  def write(path, content) when is_binary(path) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive, :monotonic])}"

    try do
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(temporary, content, [:binary, :exclusive]) do
        File.rename(temporary, path)
      end
    after
      File.rm(temporary)
    end
  end
end
